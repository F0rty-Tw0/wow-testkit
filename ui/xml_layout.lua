-- XML layout elements of frames and regions: Size, Anchors (queued in the session until their target exists), Layers,
-- KeyValues, Color and TexCoords. The helpers at the top are shared with ui/xml_widgets.lua.
local M = {}

local XmlBuild = require("ui.xml_build")

local handlers = XmlBuild.handlers

local function childNamed(node, tag)
  for _, child in ipairs(node.children) do
    if child.tag == tag then
      return child
    end
  end
  return nil
end

-- x and y of a <Size>, <Offset> or similar: the attributes, else those of its <AbsDimension> child; nil when absent.
-- source: wiki XML/Dimension, "Added x and y attributes as an alternative to AbsDimension." (row X9)
function M.dimension(node)
  local source = node
  if node.attrs.x == nil and node.attrs.y == nil then
    source = childNamed(node, "absdimension") or node
  end
  return tonumber(source.attrs.x), tonumber(source.attrs.y)
end

-- The number of a <TileSize>, <EdgeSize> or <FontHeight>: its val attribute, else that of its <AbsValue> child.
function M.absValue(node)
  local source = childNamed(node, "absvalue") or node
  return tonumber(source.attrs.val)
end

-- r, g, b and a of a <Color>.
-- source: wiki XML/Color: `a` defaults to 1.0, `r`, `g`, `b` to 0.0 (row X18)
function M.color(node)
  local attrs = node.attrs
  return tonumber(attrs.r) or 0, tonumber(attrs.g) or 0, tonumber(attrs.b) or 0, tonumber(attrs.a) or 1
end

-- Size ----------------------------------------------------------------------------------------------------------

-- Only the axes the element names change (row X9; that a second <Size> merges per axis with the first is X4, assumed).
function handlers.size(_, obj, _, node, session)
  local rel = childNamed(node, "reldimension")
  if rel then
    session.reportAt(rel.line, "<RelDimension> is not modelled; ignored")
  end
  local x, y = M.dimension(node)
  if x then
    obj:SetWidth(x)
  end
  if y then
    obj:SetHeight(y)
  end
end

-- Anchors -------------------------------------------------------------------------------------------------------

-- The widget at the end of a relativeKey path ("$parent.A.B"): `$parent` goes to the parent, any other segment is a key.
-- source: wiki XML/Anchor, relativeKey "Another widget to align against (sibling)"; row X8 (two or more levels assumed)
local function keyTarget(obj, path)
  local current = obj
  for segment in path:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return false
    end
    current = segment == "$parent" and current:GetParent() or current[segment]
  end
  return type(current) == "table", current
end

-- The global named by relativeTo, `$parent` standing for the parent's name (the parent itself when alone).
-- source: wiki XML/Anchor, relativeTo "Another widget to align against (in `_G`)"; row X8 (`$parentLeft` forms)
local function nameTarget(parent, name)
  if name == "$parent" then
    return parent ~= nil, parent
  end
  local parentName = parent and parent:GetName() or ""
  local target = rawget(_G, (name:gsub("%$parent", parentName)))
  return type(target) == "table", target
end

-- Whether the anchor's target exists yet, and it. An anchor with no target anchors to the parent, the screen when
-- there is none (rows X8 and LY1, the XML half assumed).
local function resolve(obj, parent, attrs)
  if attrs.relativekey then
    return keyTarget(obj, attrs.relativekey)
  end
  if attrs.relativeto then
    return nameTarget(parent, attrs.relativeto)
  end
  return true, parent
end

-- The offset of an <Anchor>: its <Offset> child, else its x and y attributes (row X9).
local function offsetOf(node)
  local offset = childNamed(node, "offset")
  local x, y
  if offset then
    x, y = M.dimension(offset)
  else
    x, y = tonumber(node.attrs.x), tonumber(node.attrs.y)
  end
  return x or 0, y or 0
end

-- An entry for session.anchors: try() applies the anchor once its target exists and answers whether it did.
local function anchorEntry(obj, node)
  local attrs = node.attrs
  local x, y = offsetOf(node)
  local entry = { obj = obj, line = node.line, name = attrs.relativekey or attrs.relativeto }
  -- source: wiki XML/Anchor, relativePoint "Point on the other widget to align against (defaults to the same as point)"
  function entry.try()
    local found, target = resolve(obj, obj:GetParent(), attrs)
    if found then
      obj:SetPoint(attrs.point, target, attrs.relativepoint or attrs.point, x, y)
    end
    return found
  end
  return entry
end

local function forget(session, obj)
  local kept = {}
  for _, entry in ipairs(session.anchors) do
    if entry.obj ~= obj then
      kept[#kept + 1] = entry
    end
  end
  session.anchors = kept
end

-- The element's own <Anchors> replace the points already set, queued ones included (row X4, assumed). An anchor whose
-- target is built later waits in session.anchors for XmlBuild.settle.
function handlers.anchors(_, obj, _, node, session)
  obj:ClearAllPoints()
  forget(session, obj)
  for _, anchor in ipairs(node.children) do
    if anchor.tag ~= "anchor" or not anchor.attrs.point then
      session.reportAt(anchor.line, "<" .. anchor.rawTag .. "> in <Anchors> needs a point; ignored")
    else
      local entry = anchorEntry(obj, anchor)
      if not entry.try() then
        session.anchors[#session.anchors + 1] = entry
      end
    end
  end
end

-- Layers --------------------------------------------------------------------------------------------------------

-- source: wiki XML/Layer: `level` defaults to ARTWORK, `textureSubLevel` to 0 (row X10)
function handlers.layers(w, frame, _, node, session)
  for _, layer in ipairs(node.children) do
    local level = layer.attrs.level and layer.attrs.level:upper()
    local sub = tonumber(layer.attrs.texturesublevel)
    for _, region in ipairs(layer.children) do
      XmlBuild.region(w, region, frame, session, level, sub)
    end
  end
end

-- Values ----------------------------------------------------------------------------------------------------------

-- source: wiki XML/KeyValues, example comments: `boolean` "0" is false and "on" true, `number` "two" is 0, `nil` gives
-- nil. `global` stores the global the value names (row X11, assumed); `local` is not modelled.
local KEY_TYPES = {
  string = function(value)
    return value
  end,
  number = function(value)
    return tonumber(value) or 0
  end,
  boolean = function(value)
    return value ~= "false" and value ~= "0"
  end,
  ["nil"] = function() end,
  global = function(value)
    return rawget(_G, value)
  end,
}

function handlers.keyvalues(_, obj, _, node, session)
  for _, keyValue in ipairs(node.children) do
    local typeName = keyValue.attrs.type or "string"
    local convert = KEY_TYPES[typeName]
    if convert and keyValue.attrs.key then
      obj[keyValue.attrs.key] = convert(keyValue.attrs.value)
    elseif not convert then
      session.report("keyvalue:" .. typeName, "KeyValue type '" .. typeName .. "' ignored")
    end
  end
end

-- Which setter a <Color> calls is assumed (row X18): SetColorTexture on a Texture, SetTextColor on a FontString.
function handlers.color(_, obj, _, node, session)
  if obj.SetColorTexture then
    obj:SetColorTexture(M.color(node))
  elseif obj.SetTextColor then
    obj:SetTextColor(M.color(node))
  else
    session.reportAt(node.line, "<Color> needs a Texture or FontString; ignored")
  end
end

-- source: wiki API:TextureBase_SetTexCoord, `SetTexCoord(left, right, top, bottom)` (row X18)
function handlers.texcoords(_, obj, _, node)
  local attrs = node.attrs
  obj:SetTexCoord(tonumber(attrs.left) or 0, tonumber(attrs.right) or 1, tonumber(attrs.top) or 0, tonumber(attrs.bottom) or 1)
end

return M

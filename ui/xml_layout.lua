-- XML layout elements of frames and regions: Size, Anchors (queued in the session until their target exists), Layers,
-- KeyValues, Color and TexCoords. The helpers at the top are shared with ui/xml_widgets.lua.
local M = {}

local AddonEnv = require("addon_env")
local Templates = require("ui.templates")
local XmlBuild = require("ui.xml_build")

local handlers = XmlBuild.handlers

-- The first child element of node with this (lowercased) tag, or nil.
function M.childNamed(node, tag)
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
    source = M.childNamed(node, "absdimension") or node
  end
  return tonumber(source.attrs.x), tonumber(source.attrs.y)
end

-- The number of a <TileSize>, <EdgeSize> or <FontHeight>: its val attribute, else that of its <AbsValue> child.
function M.absValue(node)
  local source = M.childNamed(node, "absvalue") or node
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
  local rel = M.childNamed(node, "reldimension")
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

-- The width and height a frame built from template `name` takes from <Size>: each template it inherits, in order, then
-- its own <Size>, an axis a later link names replacing the earlier (the order TemplateApply.applyList and handlers.size
-- apply them). nil for an axis no link names. `path` guards a template that inherits itself.
function M.templateSize(w, name, path)
  path = path or {}
  local virtual, entry = w.ui.virtuals[name], Templates.TEMPLATES[name]
  if path[name] or not (virtual or entry and (not entry.flavors or entry.flavors[w.flavor])) then
    return nil, nil
  end
  path[name] = true
  local width, height
  local inherits = virtual and { virtual.node.attrs.inherits } or entry.inherits
  for _, list in ipairs(inherits) do
    for parent in list:gmatch("[^,%s]+") do
      local parentWidth, parentHeight = M.templateSize(w, parent, path)
      width, height = parentWidth or width, parentHeight or height
    end
  end
  path[name] = nil
  local x, y
  if virtual then
    local size = M.childNamed(virtual.node, "size")
    if size then
      x, y = M.dimension(size)
    end
  elseif entry.size then
    x, y = entry.size[1], entry.size[2]
  end
  return x or width, y or height
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
local function nameTarget(w, parent, name)
  if name == "$parent" then
    return parent ~= nil, parent
  end
  local target = AddonEnv.global(w, XmlBuild.substituteParent(name, parent), true)
  return type(target) == "table", target
end

-- Whether the anchor's target exists yet, and it. An anchor with no target anchors to the parent, the screen when
-- there is none (rows X8 and LY1, the XML half assumed).
local function resolve(w, obj, parent, attrs)
  if attrs.relativekey then
    return keyTarget(obj, attrs.relativekey)
  end
  if attrs.relativeto then
    return nameTarget(w, parent, attrs.relativeto)
  end
  return true, parent
end

-- The offset of an <Anchor>: its <Offset> child, else its x and y attributes (row X9).
local function offsetOf(node)
  local offset = M.childNamed(node, "offset")
  local x, y
  if offset then
    x, y = M.dimension(offset)
  else
    x, y = tonumber(node.attrs.x), tonumber(node.attrs.y)
  end
  return x or 0, y or 0
end

-- An entry for session.anchors: try() applies the anchor once its target exists and answers whether it did. SetPoint
-- refusing the anchor (a self-anchor, a loop) is reported and the anchor dropped.
local function anchorEntry(w, session, obj, node)
  local attrs = node.attrs
  local x, y = offsetOf(node)
  local entry = { obj = obj, line = node.line, name = attrs.relativekey or attrs.relativeto }
  -- source: wiki XML/Anchor, relativePoint "Point on the other widget to align against (defaults to the same as point)"
  function entry.try()
    local found, target = resolve(w, obj, obj:GetParent(), attrs)
    if found then
      XmlBuild.guard(w, session, node.line, obj.SetPoint, obj, attrs.point, target, attrs.relativepoint or attrs.point, x, y)
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
function handlers.anchors(w, obj, _, node, session)
  obj:ClearAllPoints()
  forget(session, obj)
  for _, anchor in ipairs(node.children) do
    if anchor.tag ~= "anchor" or not anchor.attrs.point then
      session.reportAt(anchor.line, "<" .. anchor.rawTag .. "> in <Anchors> needs a point; ignored")
    else
      local entry = anchorEntry(w, session, obj, anchor)
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

-- source: confirmed (row X26) a global KeyValue names a dotted path (`MoneyDenominationDisplayType.Copper`, `AuctionHouseFrameDisplayMode.Buy`):
-- the first part is a global, each later part a field of the table before it; assumed a missing or non-table link gives nil.
local function globalPath(w, path)
  local first, rest = path:match("^([^.]*)(.*)$")
  local current = AddonEnv.global(w, first, true)
  for part in rest:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

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
  global = function(value, w)
    return globalPath(w, value)
  end,
}

function handlers.keyvalues(w, obj, _, node, session)
  for _, keyValue in ipairs(node.children) do
    local typeName = keyValue.attrs.type or "string"
    local convert = KEY_TYPES[typeName]
    if convert and keyValue.attrs.key then
      obj[keyValue.attrs.key] = convert(keyValue.attrs.value, w)
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

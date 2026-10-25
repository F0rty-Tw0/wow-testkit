-- Builds frames and regions from XML nodes. A child element of a frame goes to handlers[tag]; finishers run after a
-- frame's children are built. Element modules register themselves in both (ui/xml.lua requires them, which fixes the
-- order). A build session is one table per XML file: { ctx, file, anchors, report(key, what), reportAt(line, what) },
-- where anchors ({ obj, line, name, try() }) wait for a target that is not built yet.
local M = {}

local unpack = unpack
local AddonEnv = require("addon_env")
local Layout = require("ui.layout")
local Widgets = require("ui.widgets")
local XmlAttrs = require("ui.xml_attrs")

-- handlers[tag] = fn(w, obj, st, node, session) for a child element of a frame or region (obj).
M.handlers = {}
-- finishers[i] = fn(w, frame, st, node, session), run in order once the frame's children exist.
M.finishers = {}

-- source: wiki XML/Layer: `level` defaults to ARTWORK, `textureSubLevel` to 0 (row X10)
local DEFAULT_LAYER = "ARTWORK"
local DEFAULT_SUBLEVEL = 0
-- Region tags (lowercased by the parser) to the Ketho type, when the flavor lists it.
local REGION_TYPES = { texture = "Texture", fontstring = "FontString", line = "Line", masktexture = "MaskTexture" }

-- A session for ctx. file ({ path, seen }) names the XML file in report lines and dedupes them; without one, lines
-- name the addon.
function M.session(ctx, file)
  file = file or { path = ctx.name, seen = {} }
  local session = { ctx = ctx, file = file, anchors = {} }
  -- Adds "<path>: <what>" to the addon's report once per key per file.
  function session.report(key, what)
    if not file.seen[key] then
      file.seen[key] = true
      ctx.report[#ctx.report + 1] = file.path .. ": " .. what
    end
  end
  -- Adds "<path>:<line>: <what>" to the addon's report, every time.
  function session.reportAt(line, what)
    ctx.report[#ctx.report + 1] = file.path .. ":" .. line .. ": " .. what
  end
  return session
end

-- Calls fn(...) so an error it raises is reported (w.errors, named by the XML file and `line`) instead of aborting the
-- addon's load. True when fn did not raise.
function M.guard(w, session, line, fn, ...)
  local args = { n = select("#", ...), ... }
  local where = "addon:" .. session.ctx.name .. "/" .. session.file.path .. ":" .. line .. ": "
  return (xpcall(function()
    return fn(unpack(args, 1, args.n))
  end, function(err)
    w:reportError(where .. tostring(err))
  end))
end

local function unsupportedTag(session, node)
  session.report("tag:" .. node.tag, "unsupported XML <" .. node.rawTag .. "> ignored")
end

-- `name` with each `$parent` replaced by the parent's name; an anonymous or missing parent gives "". A function
-- replacement keeps a "%" in the parent's name literal.
-- source: wiki XML/LayoutFrame, name: "substituting `$parent` with a parent's name"; row X2 (the "" is assumed).
function M.substituteParent(name, parent)
  local parentName = parent and parent:GetName() or ""
  return (name:gsub("%$parent", function()
    return parentName
  end))
end
local substituteParent = M.substituteParent

-- The full name of the frame or region `node` builds under parent; nil when the node has no name.
function M.fullName(node, parent)
  local name = node.attrs.name
  return name and substituteParent(name, parent)
end
local fullName = M.fullName

-- source: wiki API:Object_SetParentKey "Sets a key on the parent to the child object"; wiki XML/LayoutFrame, parentArray
-- "Inserts a reference to an array in the widget's parent". The array table is created when absent (row X3, assumed).
function M.attach(parent, child, attrs)
  if not parent then
    return
  end
  if attrs.parentkey then
    parent[attrs.parentkey] = child
  end
  if attrs.parentarray then
    parent[attrs.parentarray] = parent[attrs.parentarray] or {}
    table.insert(parent[attrs.parentarray], child)
  end
end
local attach = M.attach

-- source: wiki XML, example `<Frame parent="UIParent">`: parent names a global frame. With no parent attribute a
-- top-level frame is parentless, not UIParent's child (row X1, assumed); a nested one keeps its enclosing frame.
local function parentOf(w, node, enclosing, session)
  local named = node.attrs.parent
  if not named then
    return enclosing
  end
  local parent = AddonEnv.global(w, named, true)
  if not parent then
    session.report("parent:" .. named, "parent '" .. named .. "' not found")
  end
  return parent or enclosing
end

-- Runs one child element of obj through its handler; a tag with none is reported.
function M.child(w, obj, child, session)
  local handler = M.handlers[child.tag]
  if handler then
    handler(w, obj, w.ui.state[obj], child, session)
  else
    unsupportedTag(session, child)
  end
end

-- Runs each child element of obj in document order, except that KeyValues come first (row X11: set before OnLoad; the
-- order against mixins and children is assumed).
function M.children(w, obj, node, session)
  for _, child in ipairs(node.children) do
    if child.tag == "keyvalues" then
      M.child(w, obj, child, session)
    end
  end
  for _, child in ipairs(node.children) do
    if child.tag ~= "keyvalues" then
      M.child(w, obj, child, session)
    end
  end
end

-- The content of a frame or region that a virtual template shares: attributes (inherits and mixins first), then child
-- elements.
function M.body(w, obj, node, session)
  local set = REGION_TYPES[node.tag] and XmlAttrs.region or XmlAttrs.frame
  XmlAttrs.apply(w, obj, node, session, set)
  M.children(w, obj, node, session)
end

-- Anchors that named a target built after them are retried here; those that still have none stay queued.
function M.settle(session)
  local waiting = {}
  for _, entry in ipairs(session.anchors) do
    if not entry.try() then
      waiting[#waiting + 1] = entry
    end
  end
  session.anchors = waiting
end

-- Ends a session once its file is built: a last settle, a report line for each anchor still without a target, and a
-- layout invalidation as a guard for any state the build wrote without a method (a world without widgets has none).
function M.finish(w, session)
  M.settle(session)
  for _, entry in ipairs(session.anchors) do
    session.reportAt(entry.line, "anchor target '" .. entry.name .. "' not found; anchor skipped")
  end
  session.anchors = {}
  if w.layout then
    Layout.invalidate(w)
  end
end

-- Builds `node`'s content on obj in a fresh session of the file that registered the template, the way a template is
-- applied to a frame or region that inherits it. No OnLoad here: the caller fires it once after its whole list.
function M.applyTemplate(w, obj, node, origin)
  local session = M.session(origin.ctx, origin.file)
  M.body(w, obj, node, session)
  M.finish(w, session)
end

-- Registers the virtual element `node` as template `name`; origin is the session of the file that holds it.
-- source: wiki XML/LayoutFrame, virtual: "Creates an XML virtual template instead of a widget"; row X14 (a later
-- definition replaces the earlier: assumed).
function M.registerVirtual(w, name, node, origin)
  local typeName = REGION_TYPES[node.tag] or Widgets.resolveType(w, node.rawTag)
  local applying = false
  w.ui.virtuals[name] = {
    type = typeName,
    apply = function(_, obj)
      if applying then
        error("template '" .. name .. "' inherits itself, directly or through another template", 0)
      end
      applying = true
      local ok, err = pcall(M.applyTemplate, w, obj, node, origin)
      applying = false
      if not ok then
        error(err, 0)
      end
    end,
  }
end

local function declareVirtual(w, node, session)
  if node.attrs.name then
    M.registerVirtual(w, node.attrs.name, node, session)
  else
    session.reportAt(node.line, "virtual <" .. node.rawTag .. "> needs a name; ignored")
  end
end

-- True when node is a region element (Texture, FontString, ...).
function M.isRegion(node)
  return REGION_TYPES[node.tag] ~= nil
end

-- Builds the frame `node` describes under parent. Nil when the tag is no frame type on this flavor (reported) or the
-- element is virtual (registered as a template instead).
function M.frame(w, node, parent, session)
  if not Widgets.resolveType(w, node.rawTag) then
    unsupportedTag(session, node)
    return nil
  end
  if node.attrs.virtual == "true" then
    declareVirtual(w, node, session)
    return nil
  end
  parent = parentOf(w, node, parent, session)
  local frame = Widgets.newFrame(w, node.rawTag, fullName(node, parent), parent)
  attach(parent, frame, node.attrs)
  M.body(w, frame, node, session)
  local st = w.ui.state[frame]
  for _, finish in ipairs(M.finishers) do
    finish(w, frame, st, node, session)
  end
  M.settle(session)
  return frame
end

-- Builds the region `node` describes in frame, in draw layer `layer` (default ARTWORK) at sublevel `sub` (default 0).
-- Nil when the tag is no region type on this flavor (reported) or the element is virtual (registered as a template).
function M.region(w, node, frame, session, layer, sub)
  local typeName = REGION_TYPES[node.tag]
  if not (typeName and w.globals.widgets[typeName]) then
    unsupportedTag(session, node)
    return nil
  end
  if node.attrs.virtual == "true" then
    declareVirtual(w, node, session)
    return nil
  end
  local region = w.ui.create(typeName, fullName(node, frame), frame)
  region:SetDrawLayer(layer or DEFAULT_LAYER, sub or DEFAULT_SUBLEVEL)
  attach(frame, region, node.attrs)
  M.body(w, region, node, session)
  return region
end

function M.handlers.frames(w, frame, _, node, session)
  for _, child in ipairs(node.children) do
    M.frame(w, child, frame, session)
  end
end

return M

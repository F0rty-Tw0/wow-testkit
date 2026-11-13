-- XML <Animations>: animation groups and their animations, built with the frame; nothing plays until Play (row X20,
-- the build timing and not playing assumed).
-- source: Blizzard_SharedXML/UI.xsd:1561-1646 (animations) and 1719-1738 (AnimationGroup) give the element and
-- attribute set.
local M = {}

local XmlAttrs = require("ui.xml_attrs")
local XmlBuild = require("ui.xml_build")

local handlers = XmlBuild.handlers

local unpack = unpack

local function same(value)
  return value
end

-- Attribute (lowercased) to { method, convert }. Absent methods (fromAlpha on a Translation) make the attribute ignored.
local SETTERS = {
  duration = { "SetDuration", tonumber },
  startdelay = { "SetStartDelay", tonumber },
  enddelay = { "SetEndDelay", tonumber },
  order = { "SetOrder", tonumber },
  fromalpha = { "SetFromAlpha", tonumber },
  toalpha = { "SetToAlpha", tonumber },
  degrees = { "SetDegrees", tonumber },
  smoothing = { "SetSmoothing", same },
  childkey = { "SetChildKey", same },
  targetkey = { "SetTargetKey", same },
  target = { "SetTarget", same },
  flipbookrows = { "SetFlipBookRows", tonumber },
  flipbookcolumns = { "SetFlipBookColumns", tonumber },
  flipbookframes = { "SetFlipBookFrames", tonumber },
  flipbookframewidth = { "SetFlipBookFrameWidth", tonumber },
  flipbookframeheight = { "SetFlipBookFrameHeight", tonumber },
}
-- Attributes that take part in a pair setter: SetOffset(x, y) and SetScale(x, y), the other axis at its identity.
local PAIRS = {
  { "SetOffset", "offsetx", "offsety", 0 },
  { "SetScale", "scalex", "scaley", 1 },
}
-- The attributes the pair setters read, handled apart from SETTERS.
local PAIR_AXES = {}
for _, pair in ipairs(PAIRS) do
  PAIR_AXES[pair[2]] = true
  PAIR_AXES[pair[3]] = true
end

local function setPair(animation, attrs, pair)
  local method, xName, yName, identity = unpack(pair)
  if attrs[xName] == nil and attrs[yName] == nil then
    return true
  end
  if not animation[method] then
    return false
  end
  animation[method](animation, tonumber(attrs[xName]) or identity, tonumber(attrs[yName]) or identity)
  return true
end

local function applyAttributes(animation, node, session)
  for name, value in pairs(node.attrs) do
    local setter = SETTERS[name]
    if setter and animation[setter[1]] then
      animation[setter[1]](animation, setter[2](value))
    elseif not (setter == nil and (XmlAttrs.IDENTITY[name] or PAIR_AXES[name])) then
      session.reportAt(node.line, "<" .. node.rawTag .. "> attribute '" .. name .. "' ignored")
    end
  end
  for _, pair in ipairs(PAIRS) do
    if not setPair(animation, node.attrs, pair) then
      session.reportAt(node.line, "<" .. node.rawTag .. "> attribute '" .. pair[2] .. "' ignored")
    end
  end
end

local function buildAnimation(w, group, frame, node, session)
  local ok, animation = pcall(group.CreateAnimation, group, node.rawTag, XmlBuild.fullName(node, frame))
  if not ok then
    session.reportAt(node.line, "unknown animation type '" .. node.rawTag .. "'; ignored")
    return
  end
  XmlBuild.attach(group, animation, node.attrs)
  applyAttributes(animation, node, session)
  XmlBuild.children(w, animation, node, session)
end

-- name -> node of each root virtual <AnimationGroup>, kept apart from w.ui.virtuals (frame and region templates, which
-- CreateFrame applies); made on first use.
local function groupTemplates(w)
  w.ui.groupTemplates = w.ui.groupTemplates or {}
  return w.ui.groupTemplates
end

-- Registers a root <AnimationGroup virtual="true"> as a group template; a non-virtual root group has no frame to belong
-- to and is reported.
function M.declare(w, node, session)
  if node.attrs.virtual == "true" and node.attrs.name then
    groupTemplates(w)[node.attrs.name] = node
  else
    session.reportAt(node.line, '<AnimationGroup> outside <Animations> needs virtual="true" and a name; ignored')
  end
end

-- The templates node inherits (depth first, in inherits order), then node's own attributes and children, on group.
-- source: row X35, forever 70862 blizzard_buffframe/buffframetemplates.xml:64-66 and :82, buffframe.lua:66 (the
-- template's mixin reaches the inheriting group). Assumed: a template applies as a frame template does (its parentKey
-- when the group has none, then attributes and children before the group's own).
local function groupBody(w, group, frame, node, session, seen)
  local attrs = node.attrs
  for name in (attrs.inherits or ""):gmatch("[^,%s]+") do
    local template = groupTemplates(w)[name]
    if not template then
      session.report("grouptemplate:" .. name, "animation group template '" .. name .. "' not found")
    elseif not seen[name] then
      seen[name] = true
      XmlBuild.attach(frame, group, template.attrs, w.ui.state[group])
      groupBody(w, group, frame, template, session, seen)
    end
  end
  if attrs.mixin then
    XmlAttrs.frame.mixin(w, group, w.ui.state[group], attrs.mixin, node, session)
  end
  if attrs.looping then
    group:SetLooping(attrs.looping)
  end
  if attrs.settofinalalpha then
    group:SetToFinalAlpha(attrs.settofinalalpha == "true")
  end
  for _, child in ipairs(node.children) do
    if child.tag == "scripts" then
      XmlBuild.child(w, group, child, session)
    else
      buildAnimation(w, group, frame, child, session)
    end
  end
end

local function buildGroup(w, frame, node, session)
  local group = frame:CreateAnimationGroup(XmlBuild.fullName(node, frame))
  XmlBuild.attach(frame, group, node.attrs, w.ui.state[group])
  groupBody(w, group, frame, node, session, {})
end

function handlers.animations(w, frame, _, node, session)
  for _, group in ipairs(node.children) do
    buildGroup(w, frame, group, session)
  end
end

return M

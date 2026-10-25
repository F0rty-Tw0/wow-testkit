-- XML <Animations>: animation groups and their animations, built with the frame; nothing plays until Play (row X20,
-- the build timing and not playing assumed). The element and attribute set is the schema's, Blizzard_SharedXML/UI.xsd:
-- 1561-1646 (animations) and 1719-1738 (AnimationGroup).
local M = {}

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
}
-- Attributes that take part in a pair setter: SetOffset(x, y) and SetScale(x, y), the other axis at its identity.
local PAIRS = {
  { "SetOffset", "offsetx", "offsety", 0 },
  { "SetScale", "scalex", "scaley", 1 },
}
-- Handled elsewhere: identity attributes (XmlBuild.attach) and the pair axes.
local HANDLED = { name = true, parentkey = true, parentarray = true, offsetx = true, offsety = true, scalex = true, scaley = true }

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
    elseif not (setter == nil and HANDLED[name]) then
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

local function buildGroup(w, frame, node, session)
  local attrs = node.attrs
  local group = frame:CreateAnimationGroup(XmlBuild.fullName(node, frame))
  XmlBuild.attach(frame, group, attrs)
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

function handlers.animations(w, frame, _, node, session)
  for _, group in ipairs(node.children) do
    buildGroup(w, frame, group, session)
  end
end

return M

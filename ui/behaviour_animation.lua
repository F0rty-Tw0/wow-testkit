-- AnimationGroup methods: creating animations and listing them. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Callsite = require("ui.callsite")
local Inherits = require("ui.inherits")

local unpack = unpack

local methods = {}
M.methods = methods

local function isAnimation(widgetTypes, typeName)
  if typeName == "Animation" then
    return false
  end
  for _, ancestor in ipairs(Inherits.ancestors(widgetTypes, typeName)) do
    if ancestor == "Animation" then
      return true
    end
  end

  return false
end

-- The Ketho animation type whose name equals animType ignoring case, else nil.
local function animationType(w, animType)
  if type(animType) ~= "string" then
    return nil
  end
  local widgetTypes = w.globals.widgets
  local wanted = animType:lower()
  for typeName in pairs(widgetTypes) do
    if typeName:lower() == wanted and isAnimation(widgetTypes, typeName) then
      return typeName
    end
  end

  return nil
end

function methods.CreateAnimationGroup(w, obj, _, name)
  return w.ui.create("AnimationGroup", name, obj)
end

-- inheritsFrom is accepted and ignored: animation templates are not simulated.
function methods.CreateAnimation(w, group, st, animType, name)
  local typeName = animationType(w, animType)
  if not typeName then
    error(string.format("CreateAnimation: unknown animation type '%s' on %s", tostring(animType), w.flavor), Callsite.level())
  end
  local animation = w.ui.create(typeName, name, group)
  st.animations = st.animations or {}
  st.animations[#st.animations + 1] = animation

  return animation
end

function methods.GetAnimations(_, _, st)
  return unpack(st.animations or {})
end

return M

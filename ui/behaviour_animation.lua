-- AnimationGroup methods: creating animations and listing them. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
-- Playback (Play, Stop, ...) and the animation properties register through Typed.add in ui/anim_play.lua and
-- ui/anim_params.lua, required here.
local M = {}

local Callsite = require("ui.callsite")
local Inherits = require("ui.inherits")

require("ui.anim_params")
require("ui.anim_play")

local unpack = unpack

local methods = {}
M.methods = methods

-- source: wiki API_AnimationGroup_CreateAnimation, animationType "one of: Animation (default)", Translation, Rotation, ...
local DEFAULT_TYPE = "Animation"

-- The base Animation type counts: CreateAnimation creates it by name and when no type is passed.
local function isAnimation(widgetTypes, typeName)
  for _, ancestor in ipairs(Inherits.ancestors(widgetTypes, typeName)) do
    if ancestor == "Animation" then
      return true
    end
  end

  return false
end

-- The Ketho animation type whose name equals animType ignoring case (nil means Animation), else nil.
local function animationType(w, animType)
  if animType == nil then
    animType = DEFAULT_TYPE
  end
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

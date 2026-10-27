-- Shared builders for the animation tests: a frame with a group and an Alpha animation, a script recorder, and an
-- animated widget under UIParent for the render tests.
local S = require("tests.helpers.widget_snap")

local M = {}

-- A frame with one animation group (looping loopType when given) holding one Alpha animation, 0 to 1 over 1 second.
function M.group(loopType)
  local frame = _G.CreateFrame("Frame")
  local animGroup = frame:CreateAnimationGroup()
  local alpha = animGroup:CreateAnimation("Alpha")
  alpha:SetFromAlpha(0)
  alpha:SetToAlpha(1)
  alpha:SetDuration(1)
  if loopType then
    animGroup:SetLooping(loopType)
  end

  return frame, animGroup, alpha
end

-- Records "play", "fin:<requested>", "stop" and "loop:<state>" in the returned list.
function M.recorder(animGroup)
  local log = {}
  animGroup:SetScript("OnPlay", function()
    log[#log + 1] = "play"
  end)
  animGroup:SetScript("OnFinished", function(_, requested)
    log[#log + 1] = "fin:" .. tostring(requested)
  end)
  animGroup:SetScript("OnStop", function()
    log[#log + 1] = "stop"
  end)
  animGroup:SetScript("OnLoop", function(_, loopState)
    log[#log + 1] = "loop:" .. tostring(loopState)
  end)

  return log
end

-- A frame called name (under UIParent, 100x50 at CENTER) with one group holding one animation of animType, 1 second
-- long; returns the group, the animation and the frame.
function M.animated(name, animType)
  local frame = S.anchored("Frame", name)
  local animGroup = frame:CreateAnimationGroup()
  local animation = animGroup:CreateAnimation(animType)
  animation:SetDuration(1)

  return animGroup, animation, frame
end

-- Makes animation fade from 1 to 0; returns its group.
function M.fade(animGroup, animation)
  animation:SetFromAlpha(1)
  animation:SetToAlpha(0)

  return animGroup
end

return M

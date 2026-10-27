-- UIErrorsFrame (framexml/fakes/message_frames.lua): a message frame whose AddMessage also reaches the session console.
-- The kit labels these lines "error-frame" (session_console.lua), which is what the console panel already reads.
local A = require("assert")
local Console = require("session_console")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

-- Runs fn with Console.push replaced by a recorder and returns what it recorded.
local function recording(fn)
  local pushed = {}
  local push = Console.push
  Console.push = function(_, kind, text, r, g, b)
    pushed[#pushed + 1] = { kind = kind, text = text, r = r, g = g, b = b }
  end
  local ok, err = pcall(fn)
  Console.push = push
  if not ok then
    error(err, 0)
  end

  return pushed
end

local function test_add_message_reaches_the_console_with_its_colours()
  withFrameXML("retail", function(w)
    w.console = { seq = 0, lines = {} }
    local pushed = recording(function()
      _G.UIErrorsFrame:AddMessage("bad", 1, 0, 0)
    end)
    A.same(pushed, { { kind = "error-frame", text = "bad", r = 1, g = 0, b = 0 } })
  end)
end

local function test_add_message_without_a_console_still_keeps_the_message()
  withFrameXML("retail", function()
    local pushed = recording(function()
      _G.UIErrorsFrame:AddMessage("quiet")
    end)
    A.same(pushed, {})
    A.eq(_G.UIErrorsFrame:GetNumMessages(), 1)
  end)
end

local function test_the_frame_is_a_shown_message_frame_under_ui_parent_on_every_flavor()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "retail", "forever" }) do
    withFrameXML(flavor, function()
      A.eq(_G.UIErrorsFrame:IsObjectType("ScrollingMessageFrame"), true)
      A.eq(_G.UIErrorsFrame:GetParent(), _G.UIParent)
      A.eq(_G.UIErrorsFrame:IsShown(), true)
    end)
  end
end

return function()
  test_add_message_reaches_the_console_with_its_colours()
  test_add_message_without_a_console_still_keeps_the_message()
  test_the_frame_is_a_shown_message_frame_under_ui_parent_on_every_flavor()
end

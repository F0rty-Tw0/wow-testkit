-- UIErrorsFrame: a ScrollingMessageFrame near the top of the screen. Its AddMessage keeps the message on the frame like any
-- message frame and also pushes it to the session console, when a session is running, as an "error-frame" line.
local M = {}

local Core = require("framexml.fakes.core")
local Console = require("session_console")

local FRAME_NAME = "UIErrorsFrame"
local FRAME_WIDTH, FRAME_HEIGHT = 512, 60
local FRAME_TOP = -122

-- Wraps the frame's own AddMessage; the console module is read at call time so a replaced push still takes effect.
local function forwarding(w, frame)
  local addMessage = frame.AddMessage
  frame.AddMessage = function(self, text, r, g, b, ...)
    addMessage(self, text, r, g, b, ...)
    if w.console then
      Console.push(w, "error-frame", text, r, g, b)
    end
  end
end

function M.install(w)
  local frame = Core.createNamed(w, "ScrollingMessageFrame", FRAME_NAME, _G.UIParent)
  if not frame then
    return
  end
  frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  frame:SetPoint("TOP", _G.UIParent, "TOP", 0, FRAME_TOP)
  forwarding(w, frame)
end

return M

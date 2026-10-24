-- ScrollingMessageFrame intrinsic: AddMessage, Clear and GetNumMessages (Task 6.6 owns the rest of the API).
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local MAX_MESSAGES = 120

local function test_it_is_a_frame_to_the_client_and_the_kit()
  withFrameXML("retail", function(w)
    local log = _G.CreateFrame("ScrollingMessageFrame")
    A.eq(log:GetObjectType(), "Frame")
    A.eq(log:IsObjectType("ScrollingMessageFrame"), true)
    A.eq(w.ui.state[log].plan.intrinsic, "ScrollingMessageFrame")
  end)
end

local function test_add_message_keeps_lines_in_order_white_by_default_assumed()
  withFrameXML("retail", function(w)
    local log = _G.CreateFrame("ScrollingMessageFrame")
    log:AddMessage("a", 1, 0, 0)
    log:AddMessage("b")
    A.eq(log:GetNumMessages(), 2)
    A.same(w.ui.state[log].messages, { { text = "a", r = 1, g = 0, b = 0 }, { text = "b", r = 1, g = 1, b = 1 } })
  end)
end

local function test_clear_empties_the_frame()
  withFrameXML("retail", function()
    local log = _G.CreateFrame("ScrollingMessageFrame")
    log:AddMessage("a")
    log:Clear()
    A.eq(log:GetNumMessages(), 0)
  end)
end

local function test_oldest_lines_drop_past_the_default_cap()
  withFrameXML("retail", function(w)
    local log = _G.CreateFrame("ScrollingMessageFrame")
    for i = 1, MAX_MESSAGES + 2 do
      log:AddMessage("line " .. i)
    end
    local messages = w.ui.state[log].messages
    A.eq(log:GetNumMessages(), MAX_MESSAGES)
    A.eq(messages[1].text, "line 3")
    A.eq(messages[MAX_MESSAGES].text, "line " .. (MAX_MESSAGES + 2))
  end)
end

local function test_other_widgets_keep_their_own_clear()
  withFrameXML("retail", function(w)
    local cooldown = _G.CreateFrame("Cooldown")
    cooldown:Clear()
    A.eq(w.ui.state[cooldown].messages, nil)
    A.eq(cooldown.AddMessage, nil)
  end)
end

return function()
  test_it_is_a_frame_to_the_client_and_the_kit()
  test_add_message_keeps_lines_in_order_white_by_default_assumed()
  test_clear_empties_the_frame()
  test_oldest_lines_drop_past_the_default_cap()
  test_other_widgets_keep_their_own_clear()
end

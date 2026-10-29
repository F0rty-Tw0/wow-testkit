-- Lazy Blizzard frame names: names in Ketho's Frames list resolve to inert frames, counted as unscripted.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_known_frame_name_resolves_to_frame_counted_unscripted()
  withFrameXML("retail", function(w)
    A.eq(_G.ChatConfigFrame:GetObjectType(), "Frame")
    A.eq(_G.ChatConfigFrame, _G.ChatConfigFrame)
    A.eq(w.unscripted["frame:ChatConfigFrame"], 1)
  end)
end

local function test_unknown_name_stays_nil()
  withFrameXML("retail", function()
    A.eq(_G.NotAFrameName, nil)
  end)
end

local function test_existing_globals_metatable_index_still_answers()
  local fallback = { Fallback = 1 }
  setmetatable(_G, { __index = fallback })
  local ok, err = pcall(withFrameXML, "retail", function()
    A.eq(_G.Fallback, 1)
    A.eq(_G.ChatConfigFrame:GetObjectType(), "Frame")
  end)
  setmetatable(_G, nil)
  assert(ok, err)
end

-- source: row F6, floatingchatframe.xml:540 builds each chat frame's edit box as an EditBox.
local function test_chat_frame_edit_box_names_resolve_to_edit_boxes()
  withFrameXML("retail", function(w)
    local box = _G.ChatFrame1EditBox
    A.eq(box:GetObjectType(), "EditBox")
    A.eq(pcall(box.HookScript, box, "OnEditFocusGained", function() end), true)
    A.eq(_G.ChatFrame10EditBox:GetObjectType(), "EditBox")
    A.eq(w.unscripted["frame:ChatFrame1EditBox"], 1)
  end)
end

-- source: row F8, floatingchatframe.xml:698-751 declares ChatFrame1-ChatFrame10 as ScrollingMessageFrames (an
-- intrinsic, so GetObjectType answers "Frame"; the message methods tell it from a plain Frame).
local function test_chat_frame_names_resolve_to_scrolling_message_frames()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    withFrameXML(flavor, function(w)
      local chat = _G.ChatFrame1
      A.eq(type(chat.AddMessage), "function", flavor)
      chat:AddMessage("hello")
      A.eq(chat:GetNumMessages(), 1, flavor)
      A.eq(type(_G.ChatFrame10.AddMessage), "function", flavor)
      A.eq(_G.ChatFrame1EditBox:GetObjectType(), "EditBox", flavor)
      A.eq(w.unscripted["frame:ChatFrame1"], 1, flavor)
    end)
  end
end

local function test_chat_frame_edit_boxes_are_edit_boxes_on_every_flavor_assumed()
  for _, flavor in ipairs({ "mists", "vanilla", "tbc", "forever" }) do
    withFrameXML(flavor, function()
      A.eq(_G.ChatFrame1EditBox:GetObjectType(), "EditBox")
    end)
  end
end

return function()
  test_known_frame_name_resolves_to_frame_counted_unscripted()
  test_unknown_name_stays_nil()
  test_existing_globals_metatable_index_still_answers()
  test_chat_frame_edit_box_names_resolve_to_edit_boxes()
  test_chat_frame_names_resolve_to_scrolling_message_frames()
  test_chat_frame_edit_boxes_are_edit_boxes_on_every_flavor_assumed()
end

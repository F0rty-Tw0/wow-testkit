-- Lazy Blizzard frame names: names in Ketho's Frames list resolve to inert frames, counted as unscripted.
local A = require("assert")
local B = require("tests.helpers.blizzard")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_known_frame_name_resolves_to_frame_counted_unscripted()
  withFrameXML("retail", function(w)
    A.eq(_G.ChatConfigFrame:GetObjectType(), "Frame")
    A.eq(_G.ChatConfigFrame, _G.ChatConfigFrame)
    A.eq(w.unscripted["frame:ChatConfigFrame"], 1)
  end)
end

-- source: assumed (row F9) with the Blizzard layer loaded, the client has no frame under an unloaded addon's name, so
-- Blizzard's `if Frame then Frame:Method() end` guards must see nil (a stand-in passed them and crashed).
local function test_lazy_frame_is_nil_with_the_blizzard_layer_assumed()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    B.run(B.mini(), { flavor = flavor }, function()
      A.eq(_G.ChatConfigFrame, nil, flavor)
      A.eq(_G.ChatFrame1, nil, flavor)
    end)
  end
end

-- source: assumed (row F9) without the layer every core frame is lazy, and the client always has and shows PlayerFrame
-- and ChatFrame1, so an addon frame parented to one is visible.
local function test_lazy_frame_stays_shown_without_the_blizzard_layer()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    withFrameXML(flavor, function()
      local child = _G.CreateFrame("Frame", nil, _G.PlayerFrame)
      A.same({ _G.PlayerFrame:IsShown(), _G.ChatFrame1:IsShown(), child:IsVisible() }, { true, true, true }, flavor)
    end)
  end
end

-- `tk catalog --blizzard-ui` on a flavor with no extract sets w.blizzard (blizzard_ui.lua M.load) but loads nothing;
-- the core frames must still be there.
local function test_lazy_frame_stays_shown_when_the_layer_has_no_extract()
  withFrameXML("retail", function(w)
    require("blizzard_ui").load(w, nil)
    A.eq(w.blizzard ~= nil and w.client == nil, true)
    A.eq(_G.ChatFrame1:IsShown(), true)
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
  test_lazy_frame_is_nil_with_the_blizzard_layer_assumed()
  test_lazy_frame_stays_shown_without_the_blizzard_layer()
  test_lazy_frame_stays_shown_when_the_layer_has_no_extract()
  test_unknown_name_stays_nil()
  test_existing_globals_metatable_index_still_answers()
  test_chat_frame_edit_box_names_resolve_to_edit_boxes()
  test_chat_frame_names_resolve_to_scrolling_message_frames()
  test_chat_frame_edit_boxes_are_edit_boxes_on_every_flavor_assumed()
end

-- StaticPopupDialogs, StaticPopup_Show and StaticPopup_Hide (framexml/fakes/static_popup.lua). Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_show_renders_text_and_buttons_and_accept_runs_the_handler() -- W72
  withFrameXML("retail", function()
    local accepted
    _G.StaticPopupDialogs["WD_CONFIRM"] = {
      text = "Sure?",
      button1 = "Yes",
      button2 = "No",
      OnAccept = function(_, data)
        accepted = data
      end,
    }
    local dialog = _G.StaticPopup_Show("WD_CONFIRM", nil, nil, "payload")
    A.eq(dialog, _G.StaticPopup1)
    A.eq(dialog:IsShown(), true)
    A.eq(_G.StaticPopup1Text:GetText(), "Sure?")
    A.eq(_G.StaticPopup1Button1:GetText(), "Yes")
    A.eq(_G.StaticPopup1Button2:GetText(), "No")
    _G.StaticPopup1Button1:Click()
    A.eq(accepted, "payload")
    A.eq(dialog:IsShown(), false)
  end)
end

local function test_the_dialog_is_centred_in_the_dialog_strata() -- W72
  withFrameXML("retail", function()
    _G.StaticPopupDialogs["WD_PLAIN"] = { text = "x", button1 = "Okay" }
    local dialog = _G.StaticPopup_Show("WD_PLAIN")
    A.eq(dialog:GetFrameStrata(), "DIALOG")
    A.same({ dialog:GetPoint() }, { "CENTER", _G.UIParent, "CENTER", 0, 0 })
    A.eq(dialog:GetParent(), _G.UIParent)
  end)
end

local function test_on_accept_gets_the_dialog_data_and_data2_and_a_truthy_return_keeps_it_open() -- W72
  withFrameXML("retail", function()
    local seen
    _G.StaticPopupDialogs["WD_KEEP"] = {
      text = "x",
      button1 = "Yes",
      OnAccept = function(...)
        seen = { n = select("#", ...), ... }

        return true
      end,
    }
    local dialog = _G.StaticPopup_Show("WD_KEEP", nil, nil, "d")
    dialog.data2 = "d2"
    _G.StaticPopup1Button1:Click()
    A.same({ seen[1], seen[2], seen[3], seen.n }, { dialog, "d", "d2", 3 })
    A.eq(dialog:IsShown(), true)
  end)
end

local function test_cancel_runs_on_cancel_with_clicked_and_hides() -- W72
  withFrameXML("retail", function()
    local seen
    _G.StaticPopupDialogs["WD_CANCEL"] = {
      text = "x",
      button1 = "Yes",
      button2 = "No",
      OnCancel = function(dialog, data, reason)
        seen = { dialog, data, reason }
      end,
    }
    local dialog = _G.StaticPopup_Show("WD_CANCEL", nil, nil, "d")
    _G.StaticPopup1Button2:Click()
    A.same(seen, { dialog, "d", "clicked" })
    A.eq(dialog:IsShown(), false)
  end)
end

local function test_text_arguments_are_formatted_into_the_text() -- W72
  withFrameXML("retail", function()
    _G.StaticPopupDialogs["WD_FORMAT"] = { text = "Delete %s from %s?", button1 = "Yes" }
    _G.StaticPopup_Show("WD_FORMAT", "Bob", "the list")
    A.eq(_G.StaticPopup1Text:GetText(), "Delete Bob from the list?")
  end)
end

local function test_a_dialog_without_the_second_button_hides_it() -- W72
  withFrameXML("retail", function()
    _G.StaticPopupDialogs["WD_ONE"] = { text = "x", button1 = "Okay" }
    _G.StaticPopup_Show("WD_ONE")
    A.eq(_G.StaticPopup1Button1:IsShown(), true)
    A.eq(_G.StaticPopup1Button2:IsShown(), false)
  end)
end

local function test_an_unknown_dialog_errors() -- W72
  withFrameXML("retail", function()
    A.errors(function()
      _G.StaticPopup_Show("WD_NOPE")
    end, "Dialog WD_NOPE does not exist.")
  end)
end

local function test_hide_hides_the_dialog_of_that_name_only() -- W72
  withFrameXML("retail", function()
    _G.StaticPopupDialogs["WD_A"] = { text = "a", button1 = "Okay" }
    local dialog = _G.StaticPopup_Show("WD_A")
    _G.StaticPopup_Hide("WD_B")
    A.eq(dialog:IsShown(), true)
    _G.StaticPopup_Hide("WD_A")
    A.eq(dialog:IsShown(), false)
  end)
end

-- The kit has one popup frame. The client's next free frame is missing, so Show cancels the new request and answers nil.
local function test_a_second_dialog_while_the_frame_is_busy_cancels_and_returns_nil() -- W72
  withFrameXML("retail", function()
    local cancelled
    _G.StaticPopupDialogs["WD_FIRST"] = { text = "first", button1 = "Okay" }
    _G.StaticPopupDialogs["WD_SECOND"] = {
      text = "second",
      button1 = "Okay",
      OnCancel = function(dialog, data)
        cancelled = { hadDialog = dialog ~= nil, data = data }
      end,
    }
    _G.StaticPopup_Show("WD_FIRST")
    A.eq(_G.StaticPopup_Show("WD_SECOND", nil, nil, "d"), nil)
    A.same(cancelled, { hadDialog = false, data = "d" })
    A.eq(_G.StaticPopup1Text:GetText(), "first")
  end)
end

local function test_showing_the_same_dialog_again_cancels_it_as_override_and_reuses_the_frame() -- W72
  withFrameXML("retail", function()
    local reasons = {}
    _G.StaticPopupDialogs["WD_AGAIN"] = {
      text = "x",
      button1 = "Okay",
      OnCancel = function(_, data, reason)
        reasons[#reasons + 1] = data .. ":" .. reason
      end,
    }
    local first = _G.StaticPopup_Show("WD_AGAIN", nil, nil, "one")
    local second = _G.StaticPopup_Show("WD_AGAIN", nil, nil, "two")
    A.eq(second, first)
    A.same(reasons, { "one:override" })
    A.eq(second.data, "two")
  end)
end

local function test_the_dialog_table_and_functions_exist_on_every_flavor() -- W72
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    withFrameXML(flavor, function()
      A.eq(type(_G.StaticPopupDialogs), "table")
      A.eq(type(_G.StaticPopup_Show), "function")
      A.eq(_G.StaticPopup1:IsShown(), false)
    end)
  end
end

return function()
  test_show_renders_text_and_buttons_and_accept_runs_the_handler()
  test_the_dialog_is_centred_in_the_dialog_strata()
  test_on_accept_gets_the_dialog_data_and_data2_and_a_truthy_return_keeps_it_open()
  test_cancel_runs_on_cancel_with_clicked_and_hides()
  test_text_arguments_are_formatted_into_the_text()
  test_a_dialog_without_the_second_button_hides_it()
  test_an_unknown_dialog_errors()
  test_hide_hides_the_dialog_of_that_name_only()
  test_a_second_dialog_while_the_frame_is_busy_cancels_and_returns_nil()
  test_showing_the_same_dialog_again_cancels_it_as_override_and_reuses_the_frame()
  test_the_dialog_table_and_functions_exist_on_every_flavor()
end

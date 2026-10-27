-- StaticPopupDialogs, StaticPopup_Show and StaticPopup_Hide over one dialog frame, StaticPopup1, with its text
-- (StaticPopup1Text) and two buttons (StaticPopup1Button1 and Button2). Kit-authored bodies over row W72: Show errors for
-- an unknown dialog, formats the text arguments in, labels the buttons from button1 and button2, and answers the frame;
-- clicking a button runs OnAccept(dialog, data, data2) or OnCancel(dialog, data, "clicked") and hides the dialog unless the
-- handler returns something truthy. The client's other frames (StaticPopup2 ..), timeouts, edit boxes and show conditions
-- are not modelled; with one frame, a second dialog finds none free.
local M = {}

local Core = require("framexml.fakes.core")

-- Localized: addon code may assign globals named rawget or tostring.
local rawget, tostring = rawget, tostring

-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local DIALOG_NAME = "StaticPopup1"
local DIALOG_STRATA = "DIALOG"
local DIALOG_WIDTH, DIALOG_HEIGHT = 320, 100
local TEXT_WIDTH, TEXT_TOP = 288, -16
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_BOTTOM, BUTTON_SPREAD = 110, 24, 14, 60
local BACKGROUND = { 0, 0, 0, 0.85 }
local BUTTON_BACKGROUND = { 0.2, 0.2, 0.2, 1 }
local CLICKED, OVERRIDE = "clicked", "override"

local function colored(region, color)
  region:SetColorTexture(color[1], color[2], color[3], color[4])
  region:SetAllPoints()
end

local function newButton(w, dialog, index)
  local button = w.ui.create("Button", DIALOG_NAME .. "Button" .. index, dialog)
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  colored(button:CreateTexture(nil, "BACKGROUND"), BUTTON_BACKGROUND)

  return button
end

-- The hidden dialog: centred in the DIALOG strata under UIParent, a background, the text and two buttons.
local function newDialog(w)
  local dialog = Core.createNamed(w, "Frame", DIALOG_NAME, _G.UIParent)
  if not dialog then
    return nil
  end
  dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
  dialog:SetPoint("CENTER")
  dialog:SetFrameStrata(DIALOG_STRATA)
  colored(dialog:CreateTexture(nil, "BACKGROUND"), BACKGROUND)
  local text = dialog:CreateFontString(DIALOG_NAME .. "Text", "ARTWORK", "GameFontHighlight")
  text:SetWidth(TEXT_WIDTH)
  text:SetPoint("TOP", dialog, "TOP", 0, TEXT_TOP)
  dialog.text = text
  dialog.button1, dialog.button2 = newButton(w, dialog, 1), newButton(w, dialog, 2)
  dialog:Hide()

  return dialog
end

local function dialogInfo(dialog)
  return dialog.dialogInfo or {}
end

-- source: row W72 (confirmed) blizzard_staticpopup/staticpopup.lua:712-713 a button runs the handler with the dialog, its
-- data and data2, and a truthy return keeps the dialog open. Button 2 is OnCancel and gets the reason "clicked". The
-- dialog stays up too when the handler showed another dialog in it.
local function click(dialog, index)
  local info = dialogInfo(dialog)
  local which = dialog.which
  local keepOpen
  if index == 1 then
    local onAccept = info.OnAccept or info.OnButton1
    keepOpen = onAccept and onAccept(dialog, dialog.data, dialog.data2)
  else
    local onCancel = info.OnCancel or info.OnButton2
    keepOpen = onCancel and onCancel(dialog, dialog.data, CLICKED)
  end
  if not keepOpen and which == dialog.which then
    dialog:Hide()
  end
end

-- Labels one button from the dialog's button<index> field and centres a lone first button.
local function labelButton(dialog, index, label, count)
  local button = dialog["button" .. index]
  button:SetShown(label ~= nil)
  if label ~= nil then
    button:SetText(label)
  end
  button:ClearAllPoints()
  local offset = count == 1 and 0 or (index == 1 and -BUTTON_SPREAD or BUTTON_SPREAD)
  button:SetPoint("BOTTOM", dialog, "BOTTOM", offset, BUTTON_BOTTOM)
end

local function cancelAndHide(dialog, reason)
  local onCancel = dialogInfo(dialog).OnCancel
  if onCancel then
    onCancel(dialog, dialog.data, reason)
  end
  dialog:Hide()
end

-- source: row W72 (confirmed) blizzard_staticpopup/staticpopup.lua:300 an unknown which raises "Dialog X does not exist.";
-- :392 no free dialog calls OnCancel(nil, data) and answers nil; a dialog of the same name already up is cancelled with
-- the reason "override" and reused (:380-383).
local function show(dialog)
  return function(which, textArg1, textArg2, data)
    local info = rawget(_G, "StaticPopupDialogs")[which]
    if not info then
      error("Dialog " .. tostring(which) .. " does not exist.", 2)
    end
    if dialog:IsShown() and dialog.which ~= which then
      if info.OnCancel then
        info.OnCancel(nil, data)
      end

      return nil
    elseif dialog:IsShown() then
      cancelAndHide(dialog, OVERRIDE)
    end
    dialog.which, dialog.dialogInfo, dialog.data, dialog.data2 = which, info, data, nil
    dialog.text:SetText((info.text or ""):format(textArg1 or "", textArg2 or ""))
    local count = info.button2 and 2 or 1
    labelButton(dialog, 1, info.button1, count)
    labelButton(dialog, 2, info.button2, count)
    dialog:Show()

    return dialog
  end
end

-- source: row W72 (confirmed) blizzard_staticpopup/staticpopup.lua:440 hides the dialogs of that name (and of that data
-- when data is given).
local function hide(dialog)
  return function(which, data)
    if dialog.which == which and (not data or data == dialog.data) then
      dialog:Hide()
    end
  end
end

function M.install(w)
  w:install("StaticPopupDialogs", {}, Core.GATE)
  local dialog = newDialog(w)
  if not dialog then
    return
  end
  for index, button in ipairs({ dialog.button1, dialog.button2 }) do
    w:setScript(button, "OnClick", function()
      click(dialog, index)
    end)
  end
  w:install("StaticPopup_Show", show(dialog), KETHO_GATE)
  w:install("StaticPopup_Hide", hide(dialog), KETHO_GATE)
end

return M

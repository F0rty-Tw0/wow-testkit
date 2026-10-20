-- UIDropDownMenu fake: Initialize/AddButton/Toggle build menu levels that MenuFrames renders; picks run the entry's func.
-- Sources: docs/specs/2026-10-19-input-steps-sources.md "Phase 3" (S1, S2, S4-S8, S10-S12); client paths are
-- relative to Interface/AddOns/Blizzard_SharedXML/<Mainline|Classic>/UIDropDownMenu.lua.
local M = {}

local MenuFrames = require("framexml.fakes.menu_frames")

local MAX_LEVEL = 3
local LIST_NAME = "DropDownList"
local DEFAULT_WIDTH_PADDING = 50
-- Flavors on the Mainline UIDropDownMenu.lua; the others run the Classic one (S7, S8 differ in argument counts).
local MAINLINE = { retail = true, forever = true }
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

-- S2: the client has no kinds, only flags. A title without text is a divider (Mainline :367-395, :521-523).
local function kindOf(info)
  if info.isTitle then
    local blank = info.text == nil or info.text == ""

    return blank and "divider" or "title"
  end
  if info.notCheckable then
    return "button"
  end

  return info.isNotRadio and "checkbox" or "radio"
end

local function copyInfo(info)
  local copy = {}
  for key, value in pairs(info) do
    copy[key] = value
  end

  return copy
end

-- A function-valued checked reads false until the level is shown (refreshChecked).
local function entryFor(info)
  local checkedFlag = type(info.checked) ~= "function" and info.checked
  return {
    kind = kindOf(info),
    text = info.text,
    enabled = not info.disabled,
    checked = checkedFlag and true or false,
    hasSubmenu = info.hasArrow == true,
  }
end

-- Reads a function-valued checked with the entry frame under addon context; an error is recorded and reads false.
local function readChecked(w, fn, entryFrame)
  local r = w:callAsAddon(fn, entryFrame)

  return r[1] and r[2] and true or false
end

local function refreshChecked(w, level)
  local infos = w.dropdown.infos[level]
  for index, entry in ipairs(level.entries) do
    local checked = infos[index].checked
    if type(checked) == "function" then
      entry.checked = readChecked(w, checked, entry.frame)
    end
  end
end

-- S7 (Mainline UIDropDownMenuButton_OnClick :999-1042, Classic :940-983): close the entry's own level and deeper,
-- then func. With keepShownOnClick a checkable entry flips checked instead (:1006-1017) and stays open.
local function pickEntry(w, level, depth, index, mouseButton)
  local info = w.dropdown.infos[level][index]
  local entry = level.entries[index]
  local checked = info.checked
  if type(checked) == "function" then
    checked = readChecked(w, checked, entry.frame)
  end
  if info.keepShownOnClick then
    if not info.notCheckable then
      checked = not checked
      entry.checked = checked
      if type(info.checked) ~= "function" then
        info.checked = checked
      end
    end
  else
    MenuFrames.close(w, depth)
  end
  if not info.func then
    return
  end
  if MAINLINE[w.flavor] then
    w:callAsAddon(info.func, entry.frame, info.arg1, info.arg2, checked, mouseButton)
  else
    w:callAsAddon(info.func, entry.frame, info.arg1, info.arg2, checked)
  end
end

-- S8 (Mainline UIDropDownMenuButton_OnEnter :182-191, Classic :209-218): the global ToggleDropDownMenu is looked up
-- at call time so wrappers and hooks see the call. value is info.value, else info.text (Mainline :584-590).
local function openSubmenu(w, level, depth, index)
  local open = w.menus[depth + 1]
  if open and open.parentIndex == index then
    return
  end
  local info = w.dropdown.infos[level][index]
  local entryFrame = level.entries[index].frame
  local value = info.value
  if value == nil then
    value = info.text
  end
  w.dropdown.pendingParent = index
  local ok, err
  if MAINLINE[w.flavor] then
    ok, err = pcall(_G.ToggleDropDownMenu, depth + 1, value, nil, nil, nil, nil, info.menuList, entryFrame, nil, info.menuListDisplayMode)
  else
    ok, err = pcall(_G.ToggleDropDownMenu, depth + 1, value, nil, nil, nil, nil, info.menuList, entryFrame)
  end
  w.dropdown.pendingParent = nil
  if not ok then
    error(err, 0)
  end
end

local function newLevel(w, depth, owner)
  local level = {
    entries = {},
    namePrefix = LIST_NAME .. depth,
    owner = owner,
    parentIndex = w.dropdown.pendingParent,
  }
  level.pick = function(index, mouseButton)
    pickEntry(w, level, depth, index, mouseButton)
  end
  level.openSubmenu = function(index)
    openSubmenu(w, level, depth, index)
  end

  return level
end

-- Runs frame.initialize(frame, levelArg, menuList) under addon context (not callAsAddon, so its error reaches the
-- caller, S4) with a fresh level as the AddButton target. building is restored on the error path too.
local function build(w, frame, depth, levelArg, menuList)
  local dropdown = w.dropdown
  local built = newLevel(w, depth, frame)
  local previous = dropdown.building
  dropdown.building = built
  dropdown.infos[built] = {}
  local ok, err = pcall(w.run, w, "addon", frame.initialize, frame, levelArg, menuList)
  dropdown.building = previous
  if not ok then
    error(err, 0)
  end

  return built
end

-- S4 helper (Mainline :41-65, Classic :42-66): on the open menu's frame, hide the lists from the menu level the last
-- Toggle set; on any other frame, reset that level to 1 and hide every list. The open menu is level 1's owner.
local function hideForInitialize(w, frame)
  local dropdown = w.dropdown
  local first = w.menus[1]
  if not (first and first.owner == frame) then
    dropdown.menuLevel = 1
  end
  MenuFrames.close(w, dropdown.menuLevel)
end

-- S4 (Mainline :77-99, Classic :76-97): menuList, helper close, initialize (only when init is not nil),
-- init(frame, level, menuList) with level as passed, displayMode only for "MENU" (:105-125). The scratch level
-- is dropped: nothing opens.
local function initialize(w, frame, init, displayMode, level, menuList)
  frame.menuList = menuList
  hideForInitialize(w, frame)
  if init ~= nil then
    frame.initialize = init
    build(w, frame, level or 1, level, menuList)
  end
  if displayMode == "MENU" then
    frame.displayMode = displayMode
  end
end

-- S5: the client appends to the hidden DropDownList<level>, which the next Initialize clears; the kit ignores it.
local function addButton(w, info)
  local building = w.dropdown.building
  if not building then
    return
  end
  local copy = copyInfo(info)
  local entries = building.entries
  entries[#entries + 1] = entryFor(copy)
  w.dropdown.infos[building][#entries] = copy
end

-- S1 (Mainline :1064-1071) and S6 (:1163-1165): level 1 on the owning frame closes; level 2+ falls back to level 1's owner.
local function frameFor(w, level, frame)
  if level > 1 then
    return frame or (w.menus[1] and w.menus[1].owner)
  end

  return frame
end

local function checkToggle(level, frame)
  if level > MAX_LEVEL then
    error("ToggleDropDownMenu: level " .. level .. " is past " .. LIST_NAME .. MAX_LEVEL, 3)
  end
  if not frame then
    error("ToggleDropDownMenu: no dropdown frame", 3)
  end
  if not frame.initialize then
    error("ToggleDropDownMenu: " .. tostring(frame) .. " has no initialize function; call UIDropDownMenu_Initialize first", 3)
  end
end

-- Sets the menu level Initialize hides from (S4; Mainline :1056, Classic :997). After the S1 check, hides the target
-- list and deeper before init runs (S12), and shows nothing when init added no entries (S10). anchor, x, y, button,
-- autoHideDelay and displayMode are ignored: the kit has no layout.
local function toggle(w, level, frame, menuList)
  level = level or 1
  w.dropdown.menuLevel = level
  frame = frameFor(w, level, frame)
  checkToggle(level, frame)
  local first = w.menus[1]
  if level == 1 and first and first.owner == frame then
    MenuFrames.close(w, 1)

    return
  end
  MenuFrames.close(w, level)
  local built = build(w, frame, level, level, menuList)
  if #built.entries == 0 then
    return
  end
  MenuFrames.open(w, level, built)
  refreshChecked(w, built)
end

local function setText(frame, text)
  if frame.Text then
    frame.Text:SetText(text)
  end
end

local function getText(frame)
  return frame.Text and frame.Text:GetText()
end

local function setWidth(frame, width, padding)
  frame:SetWidth(width + (padding or DEFAULT_WIDTH_PADDING))
end

local function globalsFor(w)
  return {
    UIDropDownMenu_Initialize = function(frame, init, displayMode, level, menuList)
      initialize(w, frame, init, displayMode, level, menuList)
    end,
    UIDropDownMenu_CreateInfo = function()
      return {}
    end,
    UIDropDownMenu_AddButton = function(info)
      addButton(w, info)
    end,
    ToggleDropDownMenu = function(level, _, frame, _, _, _, menuList)
      toggle(w, level, frame, menuList)
    end,
    CloseDropDownMenus = function(level)
      MenuFrames.close(w, level or 1)
    end,
    UIDropDownMenu_SetText = setText,
    UIDropDownMenu_GetText = getText,
    UIDropDownMenu_SetWidth = setWidth,
    UIDropDownMenu_SetSelectedValue = function(frame, value)
      frame.selectedValue = value
    end,
    UIDropDownMenu_GetSelectedValue = function(frame)
      return frame.selectedValue
    end,
  }
end

function M.install(w)
  if not w.globals.framexml.UIDropDownMenu_Initialize then
    return
  end
  w.dropdown = { building = nil, infos = setmetatable({}, { __mode = "k" }), pendingParent = nil, menuLevel = 1 }
  for name, fn in pairs(globalsFor(w)) do
    w:install(name, fn, KETHO_GATE)
  end
end

return M

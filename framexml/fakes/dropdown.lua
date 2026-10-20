-- UIDropDownMenu fake: Initialize/AddButton/Toggle build menu levels that MenuFrames renders; picks run the entry's func.
-- Sources: docs/client-sources.md "UIDropDownMenu" (S1, S2, S4-S8, S10-S19); client paths are
-- relative to Interface/AddOns/Blizzard_SharedXML/<Mainline|Classic>/UIDropDownMenu.lua.
local M = {}

local Callsite = require("ui.callsite")
local DropdownEntry = require("framexml.fakes.dropdown_entry")
local MenuFrames = require("framexml.fakes.menu_frames")

local LIST_NAME = "DropDownList"
local DEFAULT_WIDTH_PADDING = 50
local MAINLINE = DropdownEntry.MAINLINE
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local function newLevel(w, depth, owner)
  local level = {
    entries = {},
    namePrefix = LIST_NAME .. depth,
    owner = owner,
    parentIndex = w.dropdown.pendingParent,
  }
  level.pick = function(index, mouseButton)
    DropdownEntry.pickEntry(w, level, depth, index, mouseButton)
  end
  level.openSubmenu = function(index)
    DropdownEntry.openSubmenu(w, level, depth, index)
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
-- Toggle set; on any other frame, reset that level to 1 and hide every list. Sets UIDROPDOWNMENU_INIT_MENU (:48).
-- Only DropDownList levels hide: an open Menu API menu (levels without namePrefix, from depth 1 up) stays, and a
-- list above it still hides.
local function hideForInitialize(w, frame)
  if frame ~= rawget(_G, "UIDROPDOWNMENU_OPEN_MENU") then
    w:setGlobal("UIDROPDOWNMENU_MENU_LEVEL", 1)
  end
  w:setGlobal("UIDROPDOWNMENU_INIT_MENU", frame)
  local depth = rawget(_G, "UIDROPDOWNMENU_MENU_LEVEL")
  while w.menus[depth] and not w.menus[depth].namePrefix do
    depth = depth + 1
  end
  MenuFrames.close(w, depth)
end

-- S4 (Mainline :77-99, Classic :76-97): menuList, helper close, initialize (only when init is truthy, :83/:82),
-- init(frame, level, menuList) with level as passed, DropDownList<level or 1>.dropdown = frame (Mainline :93-94,
-- Classic :92-93), displayMode only for "MENU" (:105-125). Returns the built level, which Toggle opens; a direct
-- call drops it, so nothing opens.
local function initialize(w, frame, init, displayMode, level, menuList)
  frame.menuList = menuList
  hideForInitialize(w, frame)
  local built
  if init then
    frame.initialize = init
    built = build(w, frame, level or 1, level, menuList)
  end
  local listName = LIST_NAME .. (level or 1)
  local list = rawget(_G, listName)
  if not list then -- the client errors indexing it (Mainline :93-94); this message is the kit's (assumed)
    error("UIDropDownMenu_Initialize: no " .. listName, Callsite.level())
  end
  list.dropdown = frame
  if displayMode == "MENU" then
    frame.displayMode = displayMode
  end

  return built
end

-- UIDropDownMenu_CreateFrames (Mainline :342-356, Classic :301-315), run by AddButton and Toggle: a level past
-- UIDROPDOWNMENU_MAXLEVELS raises it and creates the list, a parentless hidden Button (S9). A kit-made list is reused.
local function createLists(w, level)
  local count = rawget(_G, "UIDROPDOWNMENU_MAXLEVELS")
  while level > count do
    count = count + 1
    w:setGlobal("UIDROPDOWNMENU_MAXLEVELS", count)
    if not rawget(_G, LIST_NAME .. count) then
      w.ui.create("Button", LIST_NAME .. count, nil):Hide()
    end
  end
end

-- S5 (Mainline :421-439, Classic :380-396): appends to DropDownList<level or 1>, the shown one at once, else the one
-- being built. Any other list is hidden and its next Initialize or Toggle clears it, so the kit drops the entry.
-- A checkable entry's function checked is called with its Button, unprotected (Mainline :650, :689-692; Classic
-- :585, :640-643), so the level is rendered first; inside init an error fails it like any init error.
local function addButton(w, info, level)
  createLists(w, level or 1)
  -- Written into the caller's table (Mainline :460-481, Classic :411-432): notClickable and isTitle disable the
  -- entry, a disabled one drops colorCode, and disablecolor replaces it.
  if info.notClickable or info.isTitle then
    info.disabled = true
  end
  if info.disabled then
    info.colorCode = nil
  end
  if info.disablecolor then
    info.colorCode = info.disablecolor
  end
  local name = LIST_NAME .. (level or 1)
  local shown = w.menus[level or 1]
  local building = w.dropdown.building
  local target = shown and shown.namePrefix == name and shown or building and building.namePrefix == name and building
  if not target then
    return
  end
  local copy = DropdownEntry.copyInfo(info)
  local entry = DropdownEntry.entryFor(copy)
  local entries = target.entries
  entries[#entries + 1] = entry
  w.dropdown.infos[target][#entries] = copy
  local callChecked = type(copy.checked) == "function" and not copy.notCheckable
  if target == shown or callChecked then
    MenuFrames.renderEntry(w, target, #entries) -- only the new button (Mainline :439, Classic :398)
  end
  if callChecked then
    entry.checked = copy.checked(entry.frame) and true or false
  end
end

-- S1 (Mainline :1064-1071, Classic :1003-1010): at any level, a shown DropDownList<level> whose open menu is frame, or
-- button's parent without one, hides. The client indexes a nil button; the kit reads that as no match.
local function closesShown(level, frame, button)
  local owner = frame or (button and button:GetParent())
  local open = rawget(_G, "UIDROPDOWNMENU_OPEN_MENU")

  return owner ~= nil and open == owner and _G[LIST_NAME .. level]:IsShown()
end

-- S6 (Mainline :1163-1165, Classic :1102-1104): level 2+ without a frame uses the open menu.
local function frameFor(level, frame)
  if level > 1 then
    return frame or rawget(_G, "UIDROPDOWNMENU_OPEN_MENU")
  end

  return frame
end

local function checkToggle(frame)
  if not frame then
    error("ToggleDropDownMenu: no dropdown frame", Callsite.level())
  end
  if not frame.initialize then
    local message = "ToggleDropDownMenu: " .. tostring(frame) .. " has no initialize function; call UIDropDownMenu_Initialize first"
    error(message, Callsite.level())
  end
end

-- Sets UIDROPDOWNMENU_MENU_LEVEL (the level Initialize hides from, S4) and _MENU_VALUE (Mainline :1056-1057, Classic
-- :997-998). After the S1 check, hides the target list and deeper before init runs (S12); level 1 then becomes
-- UIDROPDOWNMENU_OPEN_MENU (Mainline :1095, Classic :1034), and init runs through Initialize and its helper (S4).
-- Shows nothing when init added no entries (S10). anchor, x, y, autoHideDelay and displayMode are ignored: the kit
-- has no layout; button only feeds the S1 check.
local function toggle(w, level, value, frame, menuList, button)
  level = level or 1
  createLists(w, level)
  w:setGlobal("UIDROPDOWNMENU_MENU_LEVEL", level)
  w:setGlobal("UIDROPDOWNMENU_MENU_VALUE", value)
  if closesShown(level, frame, button) then
    MenuFrames.close(w, level)

    return
  end
  frame = frameFor(level, frame)
  checkToggle(frame)
  MenuFrames.close(w, level)
  if level == 1 then
    w:setGlobal("UIDROPDOWNMENU_OPEN_MENU", frame)
  end
  local built = initialize(w, frame, frame.initialize, nil, level, menuList) -- Mainline :1193, Classic :1132
  if #built.entries == 0 then
    return
  end
  MenuFrames.open(w, level, built)
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
    UIDropDownMenu_AddButton = function(info, level)
      addButton(w, info, level)
    end,
    ToggleDropDownMenu = function(level, value, frame, _, _, _, menuList, button)
      toggle(w, level, value, frame, menuList, button)
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
  w.dropdown = { building = nil, infos = setmetatable({}, { __mode = "k" }), pendingParent = nil }
  for name, fn in pairs(globalsFor(w)) do
    w:install(name, fn, KETHO_GATE)
  end
  w:setGlobal("UIDROPDOWNMENU_MAXLEVELS", MAINLINE[w.flavor] and 3 or 2) -- Mainline :4, Classic :5
  -- Mainline :12, Classic :13; OPEN_MENU, INIT_MENU and MENU_VALUE start nil. UIDropDownMenu_OnHide clears the open
  -- menu when list 1 hides (Mainline :1347-1349, Classic :1249-1251), as a script an addon's SetScript replaces.
  w:setGlobal("UIDROPDOWNMENU_MENU_LEVEL", 1)
  local list1 = rawget(_G, LIST_NAME .. 1)
  if list1 then
    w:setScript(list1, "OnHide", function()
      w:setGlobal("UIDROPDOWNMENU_OPEN_MENU", nil)
    end)
  end
end

return M

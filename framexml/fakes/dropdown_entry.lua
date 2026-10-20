-- One UIDropDownMenu entry for framexml/fakes/dropdown.lua: the kit's entry record built from an info table, and
-- what a click (pick) or a hover (submenu) on its Button does. Sources: docs/client-sources.md "UIDropDownMenu".
local M = {}

local MenuFrames = require("framexml.fakes.menu_frames")

-- Flavors on the Mainline UIDropDownMenu.lua; the others run the Classic one (S7, S8 differ in argument counts).
local MAINLINE = { retail = true, forever = true }
M.MAINLINE = MAINLINE

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

function M.copyInfo(info)
  local copy = {}
  for key, value in pairs(info) do
    copy[key] = value
  end

  return copy
end

-- A function-valued checked reads false here; addButton calls it.
function M.entryFor(info)
  local checkedFlag = type(info.checked) ~= "function" and info.checked
  return {
    kind = kindOf(info),
    text = info.text,
    enabled = not info.disabled,
    checked = checkedFlag and true or false,
    hasSubmenu = info.hasArrow == true,
  }
end

-- S7 (Mainline UIDropDownMenuButton_OnClick :999-1042, Classic :940-983): close the entry's own level and deeper,
-- then func. With keepShownOnClick a checkable entry flips checked instead (:1006-1017) and stays open. A function
-- checked is called unprotected, its value passed as is (:1000-1003): this runs inside the entry's OnClick.
function M.pickEntry(w, level, depth, index, mouseButton)
  local info = w.dropdown.infos[level][index]
  local entry = level.entries[index]
  local checked = info.checked
  if type(checked) == "function" then
    checked = checked(entry.frame)
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
function M.openSubmenu(w, level, depth, index)
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
    -- The kit's own misuse error has no position here (its Callsite walk ends at the pcall), so it gets the entry as
    -- one; an addon's error passes through as the client records it.
    if type(err) == "string" and err:find("^ToggleDropDownMenu: ") then
      err = entryFrame:GetName() .. " OnEnter: " .. err
    end
    error(err, 0)
  end
end

return M

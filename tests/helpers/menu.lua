-- Menu test helpers shared by the UIDropDownMenu, Menu API and DropdownButton tests, so their copies cannot drift
-- apart. The menu scenario tests share tests/helpers/menu_scenario.lua.
local Input = require("input")

local M = {}

-- Menu API

function M.owner()
  return _G.CreateFrame("Frame", nil, _G.UIParent)
end

function M.open(generator)
  return _G.MenuUtil.CreateContextMenu(M.owner(), generator)
end

function M.field(level, name)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry[name]
  end
  return out
end

function M.click(w, depth, index)
  Input.click(w, w.menus[depth].entries[index].frame, "LeftButton")
end

-- The entry texts of a level.
function M.levelTexts(level)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry.text
  end
  return out
end

-- Menu frames

function M.entry(kind, text, extra)
  local e = { kind = kind, text = text, enabled = true, checked = false, hasSubmenu = false }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end

-- A level recording its picks and submenu opens in log; namePrefix nil makes an unnamed (Menu API style) level.
function M.newLevel(entries, namePrefix, log)
  log = log or {}
  return {
    entries = entries,
    namePrefix = namePrefix,
    pick = function(index, button)
      log[#log + 1] = { "pick", index, button }
    end,
    openSubmenu = function(index)
      log[#log + 1] = { "open", index }
    end,
    rebuild = function() end,
  },
    log
end

-- UIDropDownMenu

-- Adds an entry from a spec { text, infoFields }.
function M.addSpec(spec, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = spec[1]
  for k, v in pairs(spec[2] or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, level)
end

-- Adds an entry with text and info fields.
function M.addFields(text, fields, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = text
  for k, v in pairs(fields or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, level)
end

-- A dropdown whose init adds items (level 1) or menuList's items (level 2); specs are { text, infoFields }.
function M.newSpecDropdown(items, name)
  local frame = _G.CreateFrame("Frame", name or "TestDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level, menuList)
    for _, spec in ipairs(level == 2 and menuList or items) do
      M.addSpec(spec, level)
    end
  end, "MENU")
  return frame
end

function M.openSpecMenu(items)
  local frame = M.newSpecDropdown(items)
  _G.ToggleDropDownMenu(1, nil, frame)
  return frame
end

-- The entry texts of the open level at depth (1 when nil).
function M.openTexts(w, depth)
  return M.levelTexts(w.menus[depth or 1])
end

-- DropdownButton

function M.newDropdownButton(generator)
  local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent, "WowStyle1DropdownTemplate")
  if generator then
    dd:SetupMenu(generator)
  end
  return dd
end

return M

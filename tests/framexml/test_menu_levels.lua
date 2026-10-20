-- Menu API fake: entering entries and the submenu levels they keep or close. Split from test_menu.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function enter(w, depth, index)
  Input.enter(w, w.menus[depth].entries[index].frame)
end

-- Menu.lua:2286-2296 (CheckForSubmenu): deeper levels collapse only when the entry's own submenu is not open; a
-- disabled Button then opens nothing. So re-entering a disabled entry whose submenu is open keeps that submenu.
local function test_entering_a_disabled_entry_whose_submenu_is_open_keeps_it()
  withFrameXML("retail", function(w)
    local flag = { on = true }
    _G.MenuUtil.CreateContextMenu(_G.CreateFrame("Frame", nil, _G.UIParent), function(_, root)
      local more = root:CreateButton("More")
      more:SetEnabled(function()
        return flag.on
      end)
      more:CreateCheckbox("Lock", function()
        return not flag.on
      end, function()
        flag.on = not flag.on
      end)
    end)
    enter(w, 1, 1)
    local sub = w.menus[2]
    -- Refresh from level 2 re-reads level 1 (Menu.lua:2259-2262): More is now disabled with its submenu open.
    Input.click(w, sub.entries[1].frame, "LeftButton")
    A.eq(w.menus[1].entries[1].enabled, false)
    enter(w, 1, 1)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2], sub)
  end)
end

return function()
  test_entering_a_disabled_entry_whose_submenu_is_open_keeps_it()
end

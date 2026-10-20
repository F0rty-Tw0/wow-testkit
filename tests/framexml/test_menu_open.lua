-- Menu API fake (menu.lua): the owner of a context menu, submenu levels and rebuild. Split from test_menu.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function noop() end

-- MenuUtil.lua:152-155: a nil ownerRegion becomes GetAppropriateTopLevelParent(), UIParent in the game.
local function test_nil_owner_becomes_ui_parent()
  withFrameXML("retail", function(w)
    local seen
    _G.MenuUtil.CreateContextMenu(nil, function(ownerArg, root)
      seen = ownerArg
      root:CreateButton("One", noop)
    end)
    A.eq(seen, _G.UIParent)
    A.eq(w.menus[1].owner, _G.UIParent)
  end)
end

local owner = HM.owner

local function enter(w, depth, index)
  Input.enter(w, w.menus[depth].entries[index].frame)
end

-- Menu.lua:2287-2290, :2038-2041 (CheckForSubmenu, GenerateSubmenu): entering an entry whose submenu is open neither
-- collapses deeper levels nor regenerates the submenu.
local function test_entering_an_entry_whose_submenu_is_open_keeps_deeper_levels()
  withFrameXML("retail", function(w)
    _G.MenuUtil.CreateContextMenu(owner(), function(_, root)
      root:CreateButton("More"):CreateButton("Deeper"):CreateButton("Deepest", noop)
    end)
    enter(w, 1, 1)
    enter(w, 2, 1)
    local second = w.menus[2]
    enter(w, 1, 1)
    A.eq(#w.menus, 3)
    A.eq(w.menus[2], second)
  end)
end

local function test_rebuild_of_a_closed_menu_does_nothing()
  withFrameXML("retail", function(w)
    local runs = 0
    local menu = _G.MenuUtil.CreateContextMenu(owner(), function(_, root)
      runs = runs + 1
      root:CreateButton("One", noop)
    end)
    local rebuild = w.menus[1].rebuild
    menu:Close()
    rebuild()
    A.eq(runs, 1)
    A.eq(#w.menus, 0)
  end)
end

local function test_rebuild_closes_a_level_whose_entry_lost_its_children()
  withFrameXML("retail", function(w)
    local nested = true
    _G.MenuUtil.CreateContextMenu(owner(), function(_, root)
      local more = root:CreateButton("More")
      if nested then
        more:CreateButton("Deep", noop)
      end
    end)
    enter(w, 1, 1)
    nested = false
    w.menus[1].rebuild()
    A.eq(#w.menus, 1)
    A.eq(w.menus[1].entries[1].hasSubmenu, false)
  end)
end

return function()
  test_nil_owner_becomes_ui_parent()
  test_entering_an_entry_whose_submenu_is_open_keeps_deeper_levels()
  test_rebuild_of_a_closed_menu_does_nothing()
  test_rebuild_closes_a_level_whose_entry_lost_its_children()
end

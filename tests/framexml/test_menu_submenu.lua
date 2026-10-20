-- Menu API fake: a two-level menu's submenu, its leaf pick, replacing and closing the menu, and rebuild.
-- Split from test_menu.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function noop() end

local function owner()
  return _G.CreateFrame("Frame", nil, _G.UIParent)
end

local function open(generator)
  return _G.MenuUtil.CreateContextMenu(owner(), generator)
end

local function field(level, name)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry[name]
  end
  return out
end

local function click(w, depth, index)
  Input.click(w, w.menus[depth].entries[index].frame, "LeftButton")
end

local function twoLevelMenu(picked)
  return function(_, root)
    root:CreateButton("Leaf", noop)
    local more = root:CreateButton("More")
    more:CreateButton("Deep", function()
      picked.deep = true
    end)
  end
end

local function test_submenu_opens_on_enter_and_lists_its_children()
  withFrameXML("retail", function(w)
    open(twoLevelMenu({}))
    A.eq(w.menus[1].entries[2].hasSubmenu, true)
    Input.enter(w, w.menus[1].entries[2].frame)
    A.same(field(w.menus[2], "text"), { "Deep" })
    A.eq(w.menus[2].parentIndex, 2)
  end)
end

local function test_submenu_leaf_pick_runs_the_callback_and_closes_every_level()
  withFrameXML("retail", function(w)
    local picked = {}
    open(twoLevelMenu(picked))
    Input.enter(w, w.menus[1].entries[2].frame)
    click(w, 2, 1)
    A.eq(picked.deep, true)
    A.eq(#w.menus, 0)
  end)
end

local function test_opening_another_menu_replaces_the_open_one()
  withFrameXML("retail", function(w)
    open(twoLevelMenu({}))
    Input.enter(w, w.menus[1].entries[2].frame)
    open(function(_, root)
      root:CreateButton("Other", noop)
    end)
    A.eq(#w.menus, 1)
    A.same(field(w.menus[1], "text"), { "Other" })
  end)
end

local function test_menu_close_closes_every_level_assumed()
  withFrameXML("retail", function(w)
    local menu = open(twoLevelMenu({}))
    Input.enter(w, w.menus[1].entries[2].frame)
    menu:Close()
    A.eq(#w.menus, 0)
  end)
end

local function test_closing_a_replaced_menu_does_not_close_the_new_one_assumed()
  withFrameXML("retail", function(w)
    local old = open(twoLevelMenu({}))
    open(twoLevelMenu({}))
    old:Close()
    A.eq(#w.menus, 1)
  end)
end

local function test_rebuild_reruns_the_generator_and_keeps_the_frames()
  withFrameXML("retail", function(w)
    local label = "Old"
    local menu = open(function(_, root)
      root:CreateButton("More"):CreateButton(label, noop)
      root:CreateButton("Second", noop)
    end)
    Input.enter(w, w.menus[1].entries[1].frame)
    local frame1, frame2 = w.menus[1].entries[1].frame, w.menus[2].frame
    label = "New"
    w.menus[1].rebuild()
    A.same(field(w.menus[2], "text"), { "New" })
    A.eq(w.menus[1].entries[1].frame, frame1)
    A.eq(w.menus[2].frame, frame2)
    A.eq(menu, w.menus[1].frame)
    menu:Close()
    A.eq(#w.menus, 0)
  end)
end

return function()
  test_submenu_opens_on_enter_and_lists_its_children()
  test_submenu_leaf_pick_runs_the_callback_and_closes_every_level()
  test_opening_another_menu_replaces_the_open_one()
  test_menu_close_closes_every_level_assumed()
  test_closing_a_replaced_menu_does_not_close_the_new_one_assumed()
  test_rebuild_reruns_the_generator_and_keeps_the_frames()
end

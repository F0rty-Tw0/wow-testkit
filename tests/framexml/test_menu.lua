-- Menu API fake: MenuUtil.CreateContextMenu, its generator and the descriptions it renders as level 1.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")

local withFrameXML = HF.withFrameXML

local function noop() end

local owner = HM.owner
local open = HM.open
local field = HM.field

local function test_installs_menu_globals_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      A.eq(type(_G.MenuUtil.CreateContextMenu), "function")
      for _, key in ipairs({ "Open", "Refresh", "Close", "CloseAll" }) do
        A.eq(type(_G.MenuResponse[key]), "number", flavor .. " MenuResponse." .. key)
      end
      A.eq(type(_G.MenuInputContext.MouseButton), "number")
    end)
  end
end

local function test_generator_gets_owner_and_root_and_fills_level_one()
  withFrameXML("retail", function(w)
    local o, seen = owner(), nil
    _G.MenuUtil.CreateContextMenu(o, function(ownerArg, root)
      seen = ownerArg
      root:CreateButton("One", noop)
      root:CreateTitle("Two")
    end)
    A.eq(seen, o)
    A.eq(w.menus[1].owner, o)
    A.eq(w.menus[1].parentIndex, nil)
    A.same(field(w.menus[1], "text"), { "One", "Two" })
  end)
end

local function test_builders_map_to_entry_kinds()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("B", noop)
      root:CreateCheckbox("C", noop, noop)
      root:CreateRadio("R", noop, noop)
      root:CreateTitle("T")
      root:CreateDivider()
    end)
    A.same(field(w.menus[1], "kind"), { "button", "checkbox", "radio", "title", "divider" })
  end)
end

local function test_checkbox_checked_comes_from_is_selected_called_with_data()
  withFrameXML("retail", function(w)
    local data, got = {}, nil
    open(function(_, root)
      root:CreateCheckbox("C", function(d)
        got = d
        return true
      end, noop, data)
    end)
    A.eq(got, data)
    A.eq(w.menus[1].entries[1].checked, true)
  end)
end

local function test_enabled_accepts_a_boolean_or_a_predicate_of_the_description()
  withFrameXML("retail", function(w)
    local seen, predicate
    open(function(_, root)
      root:CreateButton("A", noop):SetEnabled(false)
      predicate = root:CreateButton("B", noop)
      predicate:SetEnabled(function(description)
        seen = description
        return false
      end)
      root:CreateButton("C", noop)
    end)
    A.same(field(w.menus[1], "enabled"), { false, false, true })
    A.eq(seen, predicate)
  end)
end

local function test_empty_generator_opens_nothing_and_returns_nil()
  withFrameXML("retail", function(w)
    local menu = open(noop)
    A.eq(menu, nil)
    A.eq(#w.menus, 0)
  end)
end

local function test_empty_generator_still_closes_the_open_menu()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Old", noop)
    end)
    open(noop)
    A.eq(#w.menus, 0)
  end)
end

local function test_extra_arguments_reach_the_generator()
  withFrameXML("retail", function()
    local got
    _G.MenuUtil.CreateContextMenu(owner(), function(_, root, a, b)
      got = { a, b }
      root:CreateButton("X", noop)
    end, "a", "b")
    A.same(got, { "a", "b" })
  end)
end

local function test_generator_error_is_recorded_and_the_menu_opens_with_what_was_built()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Kept", noop)
      error("gen boom")
    end)
    A.eq(#w.errors, 1)
    A.same(field(w.menus[1], "text"), { "Kept" })
  end)
end

return function()
  test_installs_menu_globals_on_every_flavor()
  test_generator_gets_owner_and_root_and_fills_level_one()
  test_builders_map_to_entry_kinds()
  test_checkbox_checked_comes_from_is_selected_called_with_data()
  test_enabled_accepts_a_boolean_or_a_predicate_of_the_description()
  test_empty_generator_opens_nothing_and_returns_nil()
  test_empty_generator_still_closes_the_open_menu()
  test_extra_arguments_reach_the_generator()
  test_generator_error_is_recorded_and_the_menu_opens_with_what_was_built()
end

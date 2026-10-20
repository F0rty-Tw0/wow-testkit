-- Menu.ModifyMenu hooks, root:SetTag and UnitPopup_OpenMenu on the Menu API fake.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")

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

local UNIT_NOTE = "Blizzard's own entries are not simulated"

local function test_modify_menu_hook_runs_after_the_generator_for_the_tag()
  withFrameXML("retail", function(w)
    local ctx = {}
    local seen
    _G.Menu.ModifyMenu("MENU_X", function(ownerArg, root, contextData)
      seen = { ownerArg, contextData }
      root:CreateButton("Hook", noop)
    end)
    local o = owner()
    _G.MenuUtil.CreateContextMenu(o, function(_, root)
      root:SetTag("MENU_X", ctx)
      root:CreateButton("Own", noop)
    end)
    A.same(field(w.menus[1], "text"), { "Own", "Hook" })
    A.eq(seen[1], o)
    A.eq(seen[2], ctx)
  end)
end

local function test_modify_menu_hook_for_another_tag_does_not_run()
  withFrameXML("retail", function(w)
    _G.Menu.ModifyMenu("MENU_OTHER", function(_, root)
      root:CreateButton("Hook", noop)
    end)
    open(function(_, root)
      root:SetTag("MENU_X")
      root:CreateButton("Own", noop)
    end)
    A.same(field(w.menus[1], "text"), { "Own" })
  end)
end

local function test_modify_menu_hooks_run_in_registration_order()
  withFrameXML("retail", function(w)
    for _, name in ipairs({ "First", "Second" }) do
      _G.Menu.ModifyMenu("MENU_X", function(_, root)
        root:CreateButton(name, noop)
      end)
    end
    open(function(_, root)
      root:SetTag("MENU_X")
    end)
    A.same(field(w.menus[1], "text"), { "First", "Second" })
  end)
end

local function test_modify_menu_hook_error_is_recorded_and_the_menu_still_opens()
  withFrameXML("retail", function(w)
    _G.Menu.ModifyMenu("MENU_X", function()
      error("hook boom")
    end)
    open(function(_, root)
      root:SetTag("MENU_X")
      root:CreateButton("Own", noop)
    end)
    A.eq(#w.errors, 1)
    A.same(field(w.menus[1], "text"), { "Own" })
  end)
end

local function test_modify_menu_rejects_a_non_function()
  withFrameXML("retail", function()
    A.errors(function()
      _G.Menu.ModifyMenu("MENU_X", "nope")
    end, "ModifyMenu")
  end)
end

local function test_unit_popup_open_menu_opens_with_tag_and_context_assumed()
  withFrameXML("retail", function(w)
    local seen
    _G.Menu.ModifyMenu("MENU_UNIT_FRIEND", function(ownerArg, root, contextData)
      seen = { ownerArg, contextData }
      root:CreateButton("Hook", noop)
    end)
    local ctx = { name = "Bob" }
    _G.UnitPopup_OpenMenu("FRIEND", ctx)
    A.same(field(w.menus[1], "text"), { "Hook" })
    A.eq(seen[2], ctx)
    A.eq(seen[1]:GetObjectType(), "Frame")
    A.eq(seen[1]:GetName(), nil)
    A.eq(seen[1]:GetParent(), _G.UIParent)
  end)
end

local function test_unit_popup_open_menu_with_no_hook_opens_an_empty_menu()
  withFrameXML("retail", function(w)
    _G.UnitPopup_OpenMenu("PLAYER", {})
    A.eq(#w.menus, 1)
    A.eq(#w.menus[1].entries, 0)
  end)
end

local function test_unit_popup_open_menu_adds_the_note_once()
  withFrameXML("retail", function(w)
    _G.UnitPopup_OpenMenu("PLAYER", {})
    _G.UnitPopup_OpenMenu("FRIEND", {})
    local count = 0
    for _, note in ipairs(w.notes) do
      count = count + (note == UNIT_NOTE and 1 or 0)
    end
    A.eq(count, 1)
  end)
end

local function test_unit_popup_open_menu_is_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      A.eq(type(_G.UnitPopup_OpenMenu), "function")
      A.eq(type(_G.Menu.ModifyMenu), "function")
    end)
  end
end

return function()
  test_modify_menu_hook_runs_after_the_generator_for_the_tag()
  test_modify_menu_hook_for_another_tag_does_not_run()
  test_modify_menu_hooks_run_in_registration_order()
  test_modify_menu_hook_error_is_recorded_and_the_menu_still_opens()
  test_modify_menu_rejects_a_non_function()
  test_unit_popup_open_menu_opens_with_tag_and_context_assumed()
  test_unit_popup_open_menu_with_no_hook_opens_an_empty_menu()
  test_unit_popup_open_menu_adds_the_note_once()
  test_unit_popup_open_menu_is_on_every_flavor()
end

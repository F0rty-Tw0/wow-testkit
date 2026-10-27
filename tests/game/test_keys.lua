-- Input-state fakes: modifier keys (either side and one side), configured modified clicks, mouse buttons and the
-- button of the click being handled, all read from w.mock.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local function test_modifier_keys_follow_the_mock() -- (G6)
  G.withGame("retail", function(w)
    w:setMock({ modifiers = { shift = true } })
    A.same({
      _G.IsShiftKeyDown(),
      _G.IsModifierKeyDown(),
      _G.IsControlKeyDown(),
      _G.IsLeftShiftKeyDown(),
      _G.IsRightShiftKeyDown(),
    }, { true, true, false, true, false })
    w:setMock({ modifiers = { shift = false, rshift = true } })
    A.same({ _G.IsShiftKeyDown(), _G.IsLeftShiftKeyDown(), _G.IsRightShiftKeyDown() }, { true, false, true })
  end)
end

local function test_control_and_alt_sides_follow_the_mock() -- (G6)
  G.withGame("retail", function(w)
    w:setMock({ modifiers = { rctrl = true, lalt = true } })
    A.same({ _G.IsControlKeyDown(), _G.IsLeftControlKeyDown(), _G.IsRightControlKeyDown() }, { true, false, true })
    A.same({ _G.IsAltKeyDown(), _G.IsLeftAltKeyDown(), _G.IsRightAltKeyDown() }, { true, true, false })
    A.eq(_G.IsModifierKeyDown(), true)
  end)
end

local function test_no_modifier_is_false_not_nil() -- (G6)
  G.withGame("retail", function()
    A.same({ _G.IsShiftKeyDown(), _G.IsControlKeyDown(), _G.IsAltKeyDown(), _G.IsModifierKeyDown() }, { false, false, false, false })
  end)
end

local function test_modifier_keys_exist_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      A.eq(type(_G.IsAltKeyDown), "function", flavor)
    end)
  end
end

local function test_modified_click_reads_the_configured_modifier_assumed() -- (G7)
  G.withGame("retail", function(w)
    A.eq(_G.IsModifiedClick("CHATLINK"), false)
    w:setMock({ modifiers = { shift = true } })
    A.same({ _G.IsModifiedClick("CHATLINK"), _G.IsModifiedClick("SELFCAST") }, { true, false })
    w:setMock({ modifiedClicks = { SELFCAST = "SHIFT" } })
    A.eq(_G.IsModifiedClick("SELFCAST"), true)
  end)
end

local function test_modified_click_defaults_follow_the_settings_panel() -- (G7)
  G.withGame("retail", function(w)
    w:setMock({ modifiers = { alt = true } })
    A.same({ _G.IsModifiedClick("SELFCAST"), _G.IsModifiedClick("FOCUSCAST") }, { true, true })
    w:setMock({ modifiers = { alt = false, shift = true } })
    A.same({ _G.IsModifiedClick("PICKUPACTION"), _G.IsModifiedClick("AUTOLOOTTOGGLE") }, { true, true })
    A.eq(_G.IsModifiedClick("MOUSEOVERCAST"), false)
    w:setMock({ modifiedClicks = { SELFCAST = "NONE" } })
    A.eq(_G.IsModifiedClick("SELFCAST"), false)
  end)
end

local function test_unknown_modified_click_counts_as_unscripted_assumed() -- (G7)
  G.withGame("retail", function(w)
    A.eq(_G.IsModifiedClick("NOPE"), false)
    A.eq(w.unscripted.IsModifiedClick, 1)
  end)
end

local function test_mouse_buttons_follow_the_mock() -- (G7)
  G.withGame("retail", function(w)
    A.eq(_G.IsMouseButtonDown(), false)
    w:setMock({ buttons = { LeftButton = true } })
    A.same({ _G.IsMouseButtonDown("LeftButton"), _G.IsMouseButtonDown("RightButton"), _G.IsMouseButtonDown() }, { true, false, true })
  end)
end

return function()
  test_modifier_keys_follow_the_mock()
  test_control_and_alt_sides_follow_the_mock()
  test_no_modifier_is_false_not_nil()
  test_modifier_keys_exist_on_every_flavor()
  test_modified_click_reads_the_configured_modifier_assumed()
  test_modified_click_defaults_follow_the_settings_panel()
  test_unknown_modified_click_counts_as_unscripted_assumed()
  test_mouse_buttons_follow_the_mock()
end

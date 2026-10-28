-- State drivers and unit watches: RegisterStateDriver and its siblings, the 0.2 s throttle on the world clock and the
-- events that reset it (rows TS16-TS17). Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")

local function stateFrame(name, template)
  return _G.CreateFrame("Frame", name, _G.UIParent, template or "SecureHandlerStateTemplate")
end

local function test_state_driver_sets_the_state_attribute_and_follows_combat() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKDrv")
    local seen = {}
    f:SetScript("OnAttributeChanged", function(_, name, value)
      seen[#seen + 1] = name .. "=" .. tostring(value)
    end)
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    A.eq(f:GetAttribute("state-combat"), "calm")
    H.setCombat(w, true)
    w:advance(0.2)
    A.eq(f:GetAttribute("state-combat"), "fight")
    w:advance(0.2)
    A.same(seen, { "state-combat=calm", "state-combat=fight" }) -- no change, no second event
  end)
end

local function test_visibility_driver_hides_a_protected_frame_in_combat() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKVis", "SecureFrameTemplate")
    _G.RegisterStateDriver(f, "visibility", "[combat] hide; show")
    A.eq(f:IsShown(), true)
    H.setCombat(w, true)
    w:advance(0.2)
    A.eq(f:IsShown(), false) -- the driver is secure code: allowed in combat
    A.eq(f:GetAttribute("statehidden"), true)
    H.setCombat(w, false)
    w:advance(0.2)
    A.eq(f:IsShown(), true)
    A.eq(f:GetAttribute("statehidden"), nil)
  end)
end

local function test_state_handler_snippet_runs_on_change() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKSnip")
    f:SetAttribute("_onstate-combat", "self:SetAttribute('seen', (self:GetAttribute('seen') or '') .. newstate .. ';')")
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    H.setCombat(w, true)
    w:advance(0.2)
    w:advance(0.2)
    A.eq(f:GetAttribute("seen"), "calm;fight;")
    A.eq(#w.errors, 0)
  end)
end

local function test_unit_watch_follows_exists() -- TS16
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Button", "TKWatch", _G.UIParent, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", "focus")
    _G.RegisterUnitWatch(f)
    A.eq(_G.UnitWatchRegistered(f), true)
    A.eq(f:IsShown(), false)
    A.eq(f:GetAttribute("statehidden"), true)
    w:unit("focus", { name = "Boss" })
    w:advance(0.2)
    A.eq(f:IsShown(), true)
    A.eq(f:GetAttribute("statehidden"), nil)
    w:unit("focus", nil)
    w:advance(0.2)
    A.eq(f:IsShown(), false)
    _G.UnregisterUnitWatch(f)
    A.eq(_G.UnitWatchRegistered(f), false)
  end)
end

local function test_unit_watch_as_state_sets_state_unitexists() -- TS16
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Button", "TKWatchState", _G.UIParent, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", "focus")
    _G.RegisterUnitWatch(f, true)
    A.eq(f:GetAttribute("state-unitexists"), false)
    A.eq(f:IsShown(), true) -- state mode leaves the frame alone
    w:unit("focus", { name = "Boss" })
    w:advance(0.2)
    A.eq(f:GetAttribute("state-unitexists"), true)
  end)
end

local function test_unregister_stops_updates() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKUnreg")
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    _G.UnregisterStateDriver(f, "combat")
    H.setCombat(w, true)
    w:advance(0.2)
    A.eq(f:GetAttribute("state-combat"), "calm")
  end)
end

local function test_unregister_attribute_driver_without_attribute_removes_every_driver_of_the_frame() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKUnregAll")
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    _G.RegisterAttributeDriver(f, "foo", "[combat] 1; 2")
    _G.UnregisterAttributeDriver(f)
    H.setCombat(w, true)
    w:advance(0.2)
    A.same({ f:GetAttribute("state-combat"), f:GetAttribute("foo") }, { "calm", 2 })
  end)
end

local function test_attribute_driver_sets_a_plain_attribute() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKAttr")
    _G.RegisterAttributeDriver(f, "foo", "[combat] 7; bar")
    A.eq(f:GetAttribute("foo"), "bar")
    H.setCombat(w, true)
    w:advance(0.2)
    A.eq(f:GetAttribute("foo"), 7) -- a numeric string becomes a number
  end)
end

local function test_results_nil_and_missing_and_empty_conditional() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKNil")
    f:SetAttribute("foo", "kept")
    _G.RegisterAttributeDriver(f, "foo", "[combat] a")
    A.eq(f:GetAttribute("foo"), "kept") -- no result changes nothing
    H.setCombat(w, true)
    w:advance(0.2)
    A.eq(f:GetAttribute("foo"), "a")
    _G.RegisterAttributeDriver(f, "foo", "[nocombat] a; nil")
    A.eq(f:GetAttribute("foo"), nil) -- the string nil clears the attribute
    f:SetAttribute("foo", "again")
    _G.RegisterAttributeDriver(f, "foo", "")
    w:advance(0.2)
    A.eq(f:GetAttribute("foo"), "again") -- an empty conditional removed the driver
    A.eq(#w.timers, 0)
  end)
end

local function test_registration_from_addon_code_acts_secure_in_combat() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKTainted", "SecureFrameTemplate")
    H.setCombat(w, true)
    w:setGlobal("TKF", f)
    local r = H.run(w, "T", 'RegisterStateDriver(TKF, "visibility", "hide")')
    A.eq(r[1], true)
    A.eq(f:IsShown(), false) -- the manager hides it, not the addon
    A.eq(#H.events(w, "blocked"), 0)
  end)
end

local function test_underscore_attribute_is_refused() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKUnder")
    _G.RegisterAttributeDriver(f, "_secret", "[combat] a; b")
    A.eq(f:GetAttribute("_secret"), nil)
    A.eq(#w.timers, 0)
  end)
end

local function test_event_resets_the_throttle() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKEvent")
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    w:advance(0.2)
    H.setCombat(w, true)
    w:advance(0.05)
    A.eq(f:GetAttribute("state-combat"), "calm") -- inside the throttle window
    w:fire("PLAYER_REGEN_DISABLED")
    w:advance(0.01)
    A.eq(f:GetAttribute("state-combat"), "fight")
  end)
end

local function test_unlisted_event_does_not_reset_the_throttle() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKNoEvent")
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    w:advance(0.2)
    H.setCombat(w, true)
    w:fire("PLAYER_LOGIN")
    w:advance(0.05)
    A.eq(f:GetAttribute("state-combat"), "calm")
  end)
end

local function test_ticker_runs_only_while_a_driver_exists() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKTicker")
    A.eq(#w.timers, 0)
    _G.RegisterStateDriver(f, "combat", "[combat] fight; calm")
    A.eq(#w.timers, 1)
    _G.RegisterUnitWatch(f)
    A.eq(#w.timers, 1) -- one shared ticker
    _G.UnregisterStateDriver(f, "combat")
    A.eq(#w.timers, 1) -- the watch still needs it
    _G.UnregisterUnitWatch(f)
    A.eq(#w.timers, 0)
  end)
end

local function addonUnitExists(w)
  local cast = { n = 0 }
  w:stub("CastSpellByName", function()
    cast.n = cast.n + 1
  end)
  H.run(w, "Foo", "UnitExists = function() TK_Drv = issecure(); CastSpellByName('Fireball'); return true end")
  return cast
end

local function test_a_driver_reading_an_addon_replaced_unit_global_runs_it_tainted_assumed() -- TS4, TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKDrvT")
    local cast = addonUnitExists(w)
    H.run(w, "Foo", "RegisterStateDriver(TKDrvT, 'x', '[@target,exists] a; b')")
    w:advance(0.2)
    A.same({ _G.TK_Drv, cast.n, #H.events(w, "blocked") > 0, f:GetAttribute("state-x") }, { false, 0, true, "a" })
  end)
end

local function test_a_unit_watch_reading_an_addon_replaced_unit_exists_runs_it_tainted_assumed() -- TS4, TS16
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Button", "TKWatchT", _G.UIParent, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", "focus")
    local cast = addonUnitExists(w)
    _G.RegisterUnitWatch(f)
    w:advance(0.2)
    A.same({ _G.TK_Drv, cast.n, #H.events(w, "blocked") > 0 }, { false, 0, true })
  end)
end

local function test_an_update_error_is_reported_and_the_driver_keeps_running() -- TS16
  H.withTaint("retail", function(w)
    local f = stateFrame("TKDrvErr")
    _G.RegisterStateDriver(f, "x", "[exists] a; b")
    H.run(w, "Foo", "UnitExists = function() error('boom') end")
    w:advance(0.2)
    local first = #w.errors
    w:advance(0.2)
    A.same({ first > 0, #w.errors > first }, { true, true }) -- each update still runs and reports
    A.contains(tostring(w.errors[#w.errors].message), "boom")
  end)
end

return function()
  test_state_driver_sets_the_state_attribute_and_follows_combat()
  test_visibility_driver_hides_a_protected_frame_in_combat()
  test_state_handler_snippet_runs_on_change()
  test_unit_watch_follows_exists()
  test_unit_watch_as_state_sets_state_unitexists()
  test_unregister_stops_updates()
  test_unregister_attribute_driver_without_attribute_removes_every_driver_of_the_frame()
  test_attribute_driver_sets_a_plain_attribute()
  test_results_nil_and_missing_and_empty_conditional()
  test_registration_from_addon_code_acts_secure_in_combat()
  test_underscore_attribute_is_refused()
  test_event_resets_the_throttle()
  test_unlisted_event_does_not_reset_the_throttle()
  test_ticker_runs_only_while_a_driver_exists()
  test_a_driver_reading_an_addon_replaced_unit_global_runs_it_tainted_assumed()
  test_a_unit_watch_reading_an_addon_replaced_unit_exists_runs_it_tainted_assumed()
  test_an_update_error_is_reported_and_the_driver_keeps_running()
end

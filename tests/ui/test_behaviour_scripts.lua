-- Widget script and event methods: delegation to the world's script registry and event bus.
local A = require("assert")
local Addon = require("addon")
local HW = require("tests.helpers.widgets")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local BAD_EVENT_ROOT = TEST_DIR .. "/../fixtures/addons/BadEvent"

local withWidgets = HW.withWidgets

local function test_tooltip_set_unit_script_errors_on_retail()
  withWidgets("retail", function()
    local tip = _G.CreateFrame("GameTooltip")
    A.eq(tip:HasScript("OnTooltipSetUnit"), false)
    local message = A.errors(function()
      tip:SetScript("OnTooltipSetUnit", function() end)
    end, "OnTooltipSetUnit")
    A.contains(message, "GameTooltip")
  end)
end

local function test_tooltip_set_unit_script_works_on_vanilla()
  withWidgets("vanilla", function()
    local tip = _G.CreateFrame("GameTooltip")
    local fn = function() end
    A.eq(tip:HasScript("OnTooltipSetUnit"), true)
    tip:SetScript("OnTooltipSetUnit", fn)
    A.eq(tip:GetScript("OnTooltipSetUnit"), fn)
  end)
end

local function test_hook_script_rejects_unsupported_handler()
  withWidgets("retail", function()
    A.errors(function()
      _G.CreateFrame("Frame"):HookScript("OnClick", function() end)
    end, "OnClick")
  end)
end

local function test_hooked_script_runs_after_script()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    local order = {}
    f:SetScript("OnEvent", function()
      order[#order + 1] = "script"
    end)
    f:HookScript("OnEvent", function()
      order[#order + 1] = "hook"
    end)
    f:RegisterEvent("PLAYER_LOGIN")
    w:fire("PLAYER_LOGIN")
    A.same(order, { "script", "hook" })
  end)
end

local function test_register_unknown_event_errors_naming_event_and_flavor()
  withWidgets("vanilla", function()
    local message = A.errors(function()
      _G.CreateFrame("Frame"):RegisterEvent("NOT_AN_EVENT")
    end, "NOT_AN_EVENT")
    A.contains(message, "vanilla")
  end)
end

local function test_unknown_event_error_points_at_the_addon_line()
  withWidgets("retail", function(w)
    Addon.load(w, { name = "BadEvent", root = BAD_EVENT_ROOT })
    A.eq(#w.errors, 1)
    A.contains(tostring(w.errors[1].message), "addon:BadEvent/BadEvent.lua:3:")
  end)
end

local function test_registered_event_reaches_on_event()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    local got
    f:SetScript("OnEvent", function(self, event, unit)
      got = { self = self, event = event, unit = unit }
    end)
    f:RegisterUnitEvent("UNIT_HEALTH", "player")
    A.eq(f:IsEventRegistered("UNIT_HEALTH"), true)
    w:fire("UNIT_HEALTH", "player")
    A.same(got, { self = f, event = "UNIT_HEALTH", unit = "player" })
  end)
end

local function test_unregister_all_events_clears_registrations()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("UNIT_HEALTH")
    f:UnregisterAllEvents()
    A.eq(f:IsEventRegistered("PLAYER_LOGIN"), false)
    A.eq(f:IsEventRegistered("UNIT_HEALTH"), false)
  end)
end

local function test_unregister_event_stops_delivery()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    local count = 0
    f:SetScript("OnEvent", function()
      count = count + 1
    end)
    f:RegisterEvent("PLAYER_LOGIN")
    f:UnregisterEvent("PLAYER_LOGIN")
    w:fire("PLAYER_LOGIN")
    A.eq(count, 0)
  end)
end

return function()
  test_tooltip_set_unit_script_errors_on_retail()
  test_tooltip_set_unit_script_works_on_vanilla()
  test_hook_script_rejects_unsupported_handler()
  test_hooked_script_runs_after_script()
  test_register_unknown_event_errors_naming_event_and_flavor()
  test_unknown_event_error_points_at_the_addon_line()
  test_registered_event_reaches_on_event()
  test_unregister_all_events_clears_registrations()
  test_unregister_event_stops_delivery()
end

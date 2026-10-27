-- RegisterUnitEvent: a frame registered for units only sees events whose first argument is one of them.
local A = require("assert")
local H = require("tests.helpers.combat")

-- A frame that records the unit of every event it receives; register(frame) does the registration under test.
local function seen(register)
  local log = {}
  local frame = _G.CreateFrame("Frame")
  register(frame)
  frame:SetScript("OnEvent", function(_, _, unit)
    log[#log + 1] = unit
  end)
  return log, frame
end

local function fire(w)
  w:fire("UNIT_HEALTH", "party1")
  w:fire("UNIT_HEALTH", "target")
  w:fire("UNIT_HEALTH", "party2")
end

local function test_register_unit_event_passes_only_listed_units() -- (C15)
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "party1")
    end)
    fire(w)
    A.same(log, { "party1" })
  end)
end

local function test_two_units_are_both_passed()
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "party1", "target")
    end)
    fire(w)
    A.same(log, { "party1", "target" })
  end)
end

local function test_unit_tokens_match_without_case()
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "Party1")
    end)
    fire(w)
    A.same(log, { "party1" })
  end)
end

local function test_register_event_after_it_removes_the_filter_assumed() -- (C15)
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "party1")
      frame:RegisterEvent("UNIT_HEALTH")
    end)
    fire(w)
    A.same(log, { "party1", "target", "party2" })
  end)
end

local function test_a_repeated_unit_registration_replaces_the_old_one() -- (C15)
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "party1")
      frame:RegisterUnitEvent("UNIT_HEALTH", "target")
    end)
    fire(w)
    A.same(log, { "target" })
  end)
end

local function test_unregister_clears_the_filter()
  H.withScenario("retail", function(w)
    local log, frame = seen(function(f)
      f:RegisterUnitEvent("UNIT_HEALTH", "party1")
    end)
    frame:UnregisterEvent("UNIT_HEALTH")
    A.eq(w:passesUnitFilter(frame, "UNIT_HEALTH", "target"), true)
    frame:RegisterEvent("UNIT_HEALTH")
    fire(w)
    A.eq(#log, 3)
  end)
end

local function test_unregister_all_events_clears_the_filter()
  H.withScenario("retail", function(w)
    local log, frame = seen(function(f)
      f:RegisterUnitEvent("UNIT_HEALTH", "party1")
    end)
    frame:UnregisterAllEvents()
    frame:RegisterEvent("UNIT_HEALTH")
    fire(w)
    A.eq(#log, 3)
  end)
end

local function test_a_filter_is_per_event()
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH", "party1")
      frame:RegisterEvent("UNIT_MAXHEALTH")
    end)
    w:fire("UNIT_MAXHEALTH", "target")
    A.same(log, { "target" })
  end)
end

local function test_a_unit_registration_with_no_unit_is_a_plain_registration()
  H.withScenario("retail", function(w)
    local log = seen(function(frame)
      frame:RegisterUnitEvent("UNIT_HEALTH")
    end)
    fire(w)
    A.eq(#log, 3)
  end)
end

return function()
  test_register_unit_event_passes_only_listed_units()
  test_two_units_are_both_passed()
  test_unit_tokens_match_without_case()
  test_register_event_after_it_removes_the_filter_assumed()
  test_a_repeated_unit_registration_replaces_the_old_one()
  test_unregister_clears_the_filter()
  test_unregister_all_events_clears_the_filter()
  test_a_filter_is_per_event()
  test_a_unit_registration_with_no_unit_is_a_plain_registration()
end

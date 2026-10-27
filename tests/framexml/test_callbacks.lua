-- CallbackRegistryMixin and EventRegistry (framexml/fakes/callbacks.lua). Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function newRegistry(events)
  local registry = _G.CreateFromMixins(_G.CallbackRegistryMixin)
  registry:OnLoad()
  registry:GenerateCallbackEvents(events or { "Changed" })

  return registry
end

local function recorder()
  local calls = {}

  return calls, function(...)
    calls[#calls + 1] = { n = select("#", ...), ... }
  end
end

local function test_register_trigger_and_unregister() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local calls, fn = recorder()
    local owner = {}
    reg:RegisterCallback("Changed", fn, owner)
    reg:TriggerEvent("Changed", 1, 2)
    A.eq(#calls, 1)
    A.same({ calls[1][1], calls[1][2], calls[1][3] }, { owner, 1, 2 })
    reg:UnregisterCallback("Changed", owner)
    reg:TriggerEvent("Changed", 3)
    A.eq(#calls, 1)
  end)
end

local function test_event_registry_exists_and_triggers() -- W72
  withFrameXML("retail", function()
    local calls, fn = recorder()
    local owner = {}
    _G.EventRegistry:RegisterCallback("X", fn, owner)
    _G.EventRegistry:TriggerEvent("X", 5)
    A.same({ calls[1][1], calls[1][2] }, { owner, 5 })
  end)
end

local function test_event_registry_exists_on_every_flavor() -- W72
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    withFrameXML(flavor, function()
      A.eq(type(_G.EventRegistry.TriggerEvent), "function")
    end)
  end
end

local function test_register_returns_the_owner_and_makes_one_for_nil() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local calls, fn = recorder()
    local owner = {}
    A.eq(reg:RegisterCallback("Changed", fn, owner), owner)
    local made = reg:RegisterCallback("Changed", fn)
    A.eq(type(made), "number")
    reg:TriggerEvent("Changed")
    A.eq(#calls, 2)
  end)
end

local function test_register_rejects_a_bad_event_function_or_owner() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local function fn() end
    A.errors(function()
      reg:RegisterCallback(5, fn, {})
    end, "'event' requires string type")
    A.errors(function()
      reg:RegisterCallback("Changed", "nope", {})
    end, "'func' requires function type")
    A.errors(function()
      reg:RegisterCallback("Changed", fn, 7)
    end, "'owner' as number is reserved")
  end)
end

local function test_trigger_of_an_undefined_event_errors_unless_allowed() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    A.errors(function()
      reg:TriggerEvent("Nope")
    end, "event 'Nope' doesn't exist")
    reg:SetUndefinedEventsAllowed(true)
    reg:TriggerEvent("Nope")
  end)
end

local function test_unregister_needs_an_owner() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    A.errors(function()
      reg:UnregisterCallback("Changed")
    end, "'owner' is required")
  end)
end

local function test_extra_arguments_come_after_the_owner_and_before_the_trigger_arguments() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local calls, fn = recorder()
    local owner = {}
    reg:RegisterCallback("Changed", fn, owner, "a", "b")
    reg:TriggerEvent("Changed", 1)
    A.same({ calls[1][1], calls[1][2], calls[1][3], calls[1][4] }, { owner, "a", "b", 1 })
  end)
end

local function test_an_owner_has_one_callback_per_event() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local first, firstFn = recorder()
    local second, secondFn = recorder()
    local owner = {}
    reg:RegisterCallback("Changed", firstFn, owner)
    reg:RegisterCallback("Changed", secondFn, owner)
    reg:TriggerEvent("Changed")
    A.same({ #first, #second }, { 0, 1 })
  end)
end

local function test_generate_callback_events_refuses_a_repeat() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry({ "A" })
    A.errors(function()
      reg:GenerateCallbackEvents({ "A" })
    end, "event 'A' already exists")
    A.eq(reg.Event.A, "A")
  end)
end

local function test_a_failing_callback_reaches_the_error_handler_and_the_rest_still_run_assumed() -- W72
  withFrameXML("retail", function(w)
    local seen
    w.errorHandler = function(message)
      seen = message
    end
    local reg = newRegistry()
    local calls, fn = recorder()
    reg:RegisterCallback("Changed", function()
      error("boom", 0)
    end, {})
    reg:RegisterCallback("Changed", fn, {})
    reg:TriggerEvent("Changed")
    A.eq(seen, "boom")
    A.eq(#calls, 1)
  end)
end

local function test_the_handle_unregisters() -- W72
  withFrameXML("retail", function()
    local reg = newRegistry()
    local calls, fn = recorder()
    local handle = reg:RegisterCallbackWithHandle("Changed", fn, {})
    handle.Unregister()
    reg:TriggerEvent("Changed")
    A.eq(#calls, 0)
  end)
end

return function()
  test_register_trigger_and_unregister()
  test_event_registry_exists_and_triggers()
  test_event_registry_exists_on_every_flavor()
  test_register_returns_the_owner_and_makes_one_for_nil()
  test_register_rejects_a_bad_event_function_or_owner()
  test_trigger_of_an_undefined_event_errors_unless_allowed()
  test_unregister_needs_an_owner()
  test_extra_arguments_come_after_the_owner_and_before_the_trigger_arguments()
  test_an_owner_has_one_callback_per_event()
  test_generate_callback_events_refuses_a_repeat()
  test_a_failing_callback_reaches_the_error_handler_and_the_rest_still_run_assumed()
  test_the_handle_unregisters()
end

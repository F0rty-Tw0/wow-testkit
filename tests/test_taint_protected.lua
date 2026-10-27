-- Protected functions: a tainted call to a protected global is refused and fires ADDON_ACTION_FORBIDDEN, a combat-only
-- one is refused in combat and fires ADDON_ACTION_BLOCKED, and a call passing a secret argument to a function that does
-- not accept one raises (row TS19). Lua 5.1 only.
local A = require("assert")
local Combat = require("tests.helpers.combat")
local CombatKit = require("combat")
local Data = require("taint_protected_data")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.taint")
local HS = require("tests.helpers.session")
local Manifest = require("manifest")
local Secret = require("combat_secret_value")

-- Names the TS8 row lists that no flavour's API data has: never installed, so never gated.
local UNKNOWN = {
  "C_PingSecure.ClearPendingPingInfo",
  "C_PingSecure.GetTargetWorldPing",
  "C_PingSecure.GetTargetWorldPingAndSend",
  "C_PingSecure.SendPing",
  "C_ReportSystem.InitiateReportPlayer",
  "C_ReportSystem.SendReportPlayer",
  "C_Social.TwitterCheckStatus",
  "C_Social.TwitterConnect",
  "C_Social.TwitterDisconnect",
  "ChangeActionBarPage",
  "GuildDemote",
  "GuildPromote",
  "GuildUninvite",
  "IsItemInRange",
  "JoinBattlefield",
  "PetAssistMode",
  "ReplaceEnchant",
  "ReplaceTradeEnchant",
  "RunMacroText",
  "UseContainerItem",
}

-- A frame on both ADDON_ACTION events; the events it saw so far, each as { event, addon, function }.
local function watch(w)
  local log = Combat.watch(w, { "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" })
  return function()
    local out = {}
    for i, entry in ipairs(log) do
      out[i] = { entry.event, entry[3], entry[4] }
    end
    return out
  end
end

local function resolve(name)
  local value = _G
  for part in name:gmatch("[^.]+") do
    value = type(value) == "table" and rawget(value, part) or nil
  end
  return value
end

local function sortedNames(set)
  local names = {}
  for name in pairs(set) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function requiredArgs(signature)
  local required = 0
  for _, spec in ipairs(signature and signature.args or {}) do
    required = required + ((spec.nilable or spec.default ~= nil) and 0 or 1)
  end
  return required
end

-- The first name of set, sorted, that is an installed function taking no required argument: a call with none passes
-- Validate.check and reaches the gate.
local function callable(w, set)
  for _, name in ipairs(sortedNames(set)) do
    if type(resolve(name)) == "function" and requiredArgs(w.manifest.functions[name]) == 0 then
      return name
    end
  end
end

-- The first function (sorted) whose docs give secret.args = mode and that takes one required number or any.
local function secretTaker(w, mode)
  for _, name in ipairs(sortedNames(w.manifest.functions)) do
    local signature = w.manifest.functions[name]
    local first = signature.args and signature.args[1]
    local simple = first and (first.lua == "number" or first.lua == "any")
    if signature.secret and signature.secret.args == mode and simple and requiredArgs(signature) == 1 and type(resolve(name)) == "function" then
      return name
    end
  end
end

-- The message of the newest error the world recorded.
local function lastError(w)
  local entry = w.errors[#w.errors]
  return type(entry) == "table" and entry.message or entry
end

local function test_tainted_call_to_a_protected_function_is_blocked_and_forbidden() -- TS8, TS10
  H.withTaint("retail", function(w)
    local log = watch(w)
    local stubbed = false
    w:stub("CastSpellByName", function()
      stubbed = true
    end)
    local result = H.run(w, "Foo", "return CastSpellByName('Fireball')")
    A.eq(stubbed, false) -- blocked before the stub
    A.same({ result.n, result[1] }, { 1, true }) -- returns nothing
    A.same(log(), { { "ADDON_ACTION_FORBIDDEN", "Foo", "CastSpellByName()" } })
    local entry = w.taint.log[1]
    A.same({ entry.kind, entry.event, entry.addon, entry.name }, { "blocked", "ADDON_ACTION_FORBIDDEN", "Foo", "CastSpellByName()" })
    A.eq(entry.text, "CastSpellByName() blocked: execution tainted by Foo")
  end)
end

local function test_secure_caller_may_call_a_protected_function() -- TS8
  H.withTaint("retail", function(w)
    local name = callable(w, Data.protected)
    A.truthy(name, "TS8 lists a protected function present on retail that takes no required argument")
    local stubbed = false
    w:stub(name, function()
      stubbed = true
    end)
    w:run("blizzard", resolve(name))
    A.eq(stubbed, true)
    A.eq(#H.events(w, "blocked"), 0)
  end)
end

local function test_namespaced_protected_function_is_blocked() -- TS8
  H.withTaint("retail", function(w)
    local log = watch(w)
    local stubbed = false
    w:stub("C_Item.ConfirmBindOnUse", function()
      stubbed = true
    end)
    H.run(w, "Foo", "C_Item.ConfirmBindOnUse()")
    A.eq(stubbed, false)
    A.same(log(), { { "ADDON_ACTION_FORBIDDEN", "Foo", "C_Item.ConfirmBindOnUse()" } })
  end)
end

local function test_compare_item_is_protected() -- TS8 (the extract flags it, api/retail does not)
  A.eq(Data.protected["C_TooltipComparison.CompareItem"], true)
end

local function test_combat_only_function_is_blocked_only_in_combat_assumed() -- TS10
  H.withTaint("retail", function(w)
    local name = callable(w, Data.noCombat)
    A.truthy(name, "TS8 lists a combat-only function present on retail")
    local log = watch(w)
    H.run(w, "Foo", name .. "()")
    A.same(log(), {})
    H.setCombat(w, true)
    H.run(w, "Foo", name .. "()")
    A.same(log(), { { "ADDON_ACTION_BLOCKED", "Foo", name .. "()" } })
    w:run("blizzard", resolve(name)) -- secure code may, in combat too
    A.eq(#log(), 1)
  end)
end

local function test_protected_function_is_blocked_outside_combat_too_assumed() -- TS10
  H.withTaint("retail", function(w)
    local name = callable(w, Data.protected)
    A.truthy(name)
    local log = watch(w)
    H.setCombat(w, false)
    H.run(w, "Foo", name .. "()")
    A.same(log(), { { "ADDON_ACTION_FORBIDDEN", "Foo", name .. "()" } })
  end)
end

local function test_blocked_in_combat_shows_the_interface_message_once_assumed() -- TS11
  HS.withSession(nil, function(sess)
    local w = sess.w
    H.setCombat(w, true)
    H.run(w, "Foo", "PickupAction() PickupAction()")
    local chat = {}
    for _, line in ipairs(sess:call("console", { since = 0 }).lines) do
      if line.kind == "chat" then
        chat[#chat + 1] = line
      end
    end
    A.eq(#chat, 1)
    A.eq(chat[1].text, rawget(_G, "INTERFACE_ACTION_BLOCKED") or "Interface action failed because of an AddOn")
    A.eq(#H.events(w, "blocked"), 2)
  end)
end

local function test_forbidden_shows_the_static_popup_assumed() -- TS11
  H.withTaint("retail", function(w)
    H.run(w, "Foo", "CastSpellByName('x')")
    local dialog = rawget(_G, "StaticPopupDialogs").ADDON_ACTION_FORBIDDEN
    A.truthy(dialog, "the kit defines the dialog when the client's has not")
    dialog.text = "%s blocked"
    H.run(w, "Foo", "CastSpellByName('y')")
    A.same({ _G.StaticPopup1:IsShown(), _G.StaticPopup1.which, _G.StaticPopup1.data }, { true, "ADDON_ACTION_FORBIDDEN", "Foo" })
    A.eq(_G.StaticPopup1Text:GetText(), "Foo blocked")
  end)
end

local function test_handler_that_calls_a_protected_function_does_not_recurse()
  H.withTaint("retail", function(w)
    local log = watch(w)
    H.run(
      w,
      "Foo",
      "local f = CreateFrame('Frame') f:RegisterEvent('ADDON_ACTION_FORBIDDEN') f:SetScript('OnEvent', function() CastSpellByName('inner') end)"
    )
    H.run(w, "Foo", "CastSpellByName('outer')")
    A.eq(#log(), 1)
    A.eq(#H.events(w, "blocked"), 2)
  end)
end

local function test_enforce_off_passes_calls_through()
  H.withTaint("retail", function(w)
    local stubbed = false
    w:stub("CastSpellByName", function()
      stubbed = true
    end)
    w.taint.enforce = false
    H.run(w, "Foo", "CastSpellByName('Fireball')")
    A.eq(stubbed, true)
    A.eq(#H.events(w, "blocked"), 0)
  end)
end

local function test_every_listed_name_is_a_known_api_function()
  local known = {}
  for _, flavor in ipairs(Flavors.list) do
    local manifest, globals = Manifest.load(flavor)
    for _, set in ipairs({ Data.protected, Data.noCombat }) do
      for name in pairs(set) do
        if manifest.functions[name] or globals.api[name] then
          known[name] = true
        end
      end
    end
  end
  local missing = {}
  for _, set in ipairs({ Data.protected, Data.noCombat }) do
    for name in pairs(set) do
      if not known[name] then
        missing[#missing + 1] = name
      end
    end
  end
  table.sort(missing)
  A.same(missing, UNKNOWN)
end

local function test_calls_on_flavours_without_the_name_are_untouched()
  H.withTaint("vanilla", function(w)
    A.eq(Data.protected["C_Container.UseHearthstone"], true)
    A.eq(resolve("C_Container.UseHearthstone"), nil) -- not on vanilla: nothing installed, nothing gated
    local result = H.run(w, "Foo", "return C_Container.UseHearthstone == nil")
    A.same({ result[1], result[2] }, { true, true })
    A.eq(#H.events(w, "blocked"), 0)
  end)
end

local function test_blocking_is_per_execution_not_per_addon()
  H.withTaint("retail", function(w)
    local stubbed = 0
    w:stub("CastSpellByName", function()
      stubbed = stubbed + 1
    end)
    H.run(w, "Foo", "C_Timer.After(0, function() CastSpellByName('timer') end)")
    w:advance(1)
    A.eq(stubbed, 0)
    A.eq(#H.events(w, "blocked"), 1)
    w:run("blizzard", function()
      _G.CastSpellByName("secure")
    end)
    A.eq(stubbed, 1)
  end)
end

local function test_tainted_call_with_secret_arg_is_refused_assumed() -- TS19
  H.withTaint("retail", function(w)
    CombatKit.install(w) -- its realType lets Validate see a secret argument's type
    local name = secretTaker(w, "AllowedWhenUntainted")
    A.truthy(name)
    w:setGlobal("TKSecret", Secret.make(5, w))
    local result = H.run(w, "Foo", name .. "(TKSecret)")
    A.eq(result[1], false)
    A.contains(lastError(w), name)
    A.contains(lastError(w), "secret")
    w:run("blizzard", resolve(name), Secret.make(5, w)) -- untainted code may
    A.eq(H.run(w, "Foo", "return AbbreviateNumbers(TKSecret)")[1], true) -- AllowedWhenTainted accepts it from anyone
  end)
end

local function test_not_allowed_refuses_a_secret_from_every_caller_assumed() -- TS19
  H.withTaint("retail", function(w)
    CombatKit.install(w)
    local name = secretTaker(w, "NotAllowed")
    A.truthy(name)
    w:setGlobal("TKSecret", Secret.make(5, w))
    A.eq(H.run(w, "Foo", name .. "(TKSecret)")[1], false)
    A.errors(function()
      w:run("blizzard", resolve(name), Secret.make(5, w))
    end, name)
  end)
end

return function()
  test_tainted_call_to_a_protected_function_is_blocked_and_forbidden()
  test_secure_caller_may_call_a_protected_function()
  test_namespaced_protected_function_is_blocked()
  test_compare_item_is_protected()
  test_combat_only_function_is_blocked_only_in_combat_assumed()
  test_protected_function_is_blocked_outside_combat_too_assumed()
  test_blocked_in_combat_shows_the_interface_message_once_assumed()
  test_forbidden_shows_the_static_popup_assumed()
  test_handler_that_calls_a_protected_function_does_not_recurse()
  test_enforce_off_passes_calls_through()
  test_every_listed_name_is_a_known_api_function()
  test_calls_on_flavours_without_the_name_are_untouched()
  test_blocking_is_per_execution_not_per_addon()
  test_tainted_call_with_secret_arg_is_refused_assumed()
  test_not_allowed_refuses_a_secret_from_every_caller_assumed()
end

-- Retail secret values: restrictions and their events, secret returns for addon callers, the operations a secret refuses,
-- the combat log payload, and the snapshot reading a secret text. Lua 5.1 only (the secret is a newproxy userdata).
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.combat")
local Log = require("combat_log")
local Secret = require("combat_secret")
local Snapshot = require("snapshot")
local State = require("combat_state")
local WidgetSnap = require("tests.helpers.widget_snap")

local unpack = unpack

local RESTRICTION = { Combat = 0, Encounter = 1, Chat = 5 }
local INACTIVE, ACTIVATING, ACTIVE = 0, 1, 2

local function asAddon(w, fn, ...)
  return w:run("addon", fn, ...)
end

local function test_health_is_secret_for_addons_in_combat_only()
  H.withCombat("retail", function(w)
    H.pair(w)
    A.eq(asAddon(w, _G.UnitHealth, "party1"), 1000) -- no restriction: real
    Secret.setRestriction(w, "Combat", true)
    local v = asAddon(w, _G.UnitHealth, "party1")
    A.eq(_G.issecretvalue(v), true)
    A.errors(function()
      return v + 1
    end, "secret number")
    A.eq(w:run("blizzard", _G.UnitHealth, "party1"), 1000) -- engine context sees the real value
    A.eq(Secret.reveal(v), 1000)
  end)
end

local function test_restriction_events_and_api()
  H.withCombat("retail", function(w)
    local log = H.watch(w, { "ADDON_RESTRICTION_STATE_CHANGED" })
    Secret.setRestriction(w, "Encounter", true)
    A.same({ log[1][3], log[1][4], log[2][3], log[2][4] }, { RESTRICTION.Encounter, ACTIVATING, RESTRICTION.Encounter, ACTIVE })
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Encounter), true)
    A.eq(_G.C_RestrictedActions.GetAddOnRestrictionState(RESTRICTION.Encounter), ACTIVE)
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Combat), false)
    Secret.setRestriction(w, "Encounter", false)
    A.same({ #log, log[3][3], log[3][4] }, { 3, RESTRICTION.Encounter, INACTIVE })
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Encounter), false)
    A.errors(function()
      Secret.setRestriction(w, "Nope", true)
    end, "valid:")
  end)
end

local function test_secret_operations_error_in_addon_code_assumed() -- (C16)
  H.withCombat("retail", function(w)
    local number, other = Secret.make(7, w), Secret.make(8, w)
    local text, tbl, fn = Secret.make("abc", w), Secret.make({ 1 }, w), Secret.make(print, w)
    A.errors(function()
      return number * 2
    end, "attempt to perform arithmetic on a secret number value")
    A.errors(function()
      return -number
    end, "secret number")
    A.errors(function()
      return number < other
    end, "attempt to perform comparison on a secret number value")
    A.errors(function()
      return number <= other
    end, "secret number")
    A.errors(function()
      return number < 9 -- Lua 5.1 refuses a userdata against a number before any metamethod: its own message
    end)
    A.errors(function()
      return number == other
    end, "secret number")
    A.errors(function()
      return #text
    end, "attempt to perform length on a secret string value")
    A.errors(function()
      return tbl[1]
    end, "attempt to perform index on a secret table value")
    A.errors(function()
      tbl.x = 1
    end, "secret table")
    A.errors(function()
      return fn()
    end, "secret function")
    A.errors(function()
      return tbl .. "x"
    end, "attempt to perform concatenation on a secret table value")
    A.eq(number == 7, false) -- a secret against a plain value is not equal and does not raise
  end)
end

local function test_concatenation_and_truthiness_stay_allowed_assumed() -- (C16)
  H.withCombat("retail", function(w)
    local text, number = Secret.make("abc", w), Secret.make(7, w)
    local joined = "x" .. text .. number
    A.eq(_G.issecretvalue(joined), true)
    A.eq(Secret.reveal(joined), "xabc7")
    A.eq(text and true, true)
    A.eq(_G.hasanysecretvalues(1, text), true)
    A.eq(_G.hasanysecretvalues(1, "a"), false)
  end)
end

local function test_engine_context_operates_on_the_real_value()
  H.withCombat("retail", function(w)
    local number, text, tbl = Secret.make(7, w), Secret.make("abc", w), Secret.make({ 5 }, w)
    local nine = Secret.make(9, w)
    A.same({ w:run("blizzard", function()
      return number + 1, #text, tbl[1], number < nine, "z" .. text
    end) }, { 8, 3, 5, true, "zabc" })
    A.eq(_G.canaccessvalue(number), false) -- an addon (here: no engine context) cannot
    A.eq(w:run("blizzard", _G.canaccessvalue, number), true)
    A.eq(_G.canaccessvalue(5), true)
  end)
end

local function test_non_secret_functions_stay_plain()
  H.withCombat("retail", function(w)
    H.pair(w)
    Secret.setRestriction(w, "Combat", true)
    A.eq(_G.issecretvalue(asAddon(w, _G.GetTime)), false) -- secret.returns = "never"
    A.eq(_G.issecretvalue(asAddon(w, _G.InCombatLockdown)), false)
    A.eq(_G.issecretvalue(asAddon(w, _G.UnitName, "party1")), true) -- secret.when = UnitNameIdentityRestricted
    Secret.setRestriction(w, "Combat", false)
    A.eq(asAddon(w, _G.UnitName, "party1"), "Ann")
  end)
end

local function test_when_conditions_follow_their_restriction_assumed() -- (C16)
  H.withCombat("retail", function(w)
    w:install("C_EncounterTimeline.GetEventInfo", function()
      return { id = 1 }
    end)
    local function secretNow(fn, ...)
      return _G.issecretvalue(asAddon(w, fn, ...))
    end
    A.same({ secretNow(_G.C_EncounterTimeline.GetEventInfo, 1), secretNow(_G.C_Club.GetSubscribedClubs) }, { false, false })
    Secret.setRestriction(w, "Combat", true)
    A.same({ secretNow(_G.C_EncounterTimeline.GetEventInfo, 1), secretNow(_G.C_Club.GetSubscribedClubs) }, { false, false })
    Secret.setRestriction(w, "Combat", false)
    Secret.setRestriction(w, "Encounter", true)
    A.same({ secretNow(_G.C_EncounterTimeline.GetEventInfo, 1), secretNow(_G.C_Club.GetSubscribedClubs) }, { true, false })
    Secret.setRestriction(w, "Encounter", false)
    Secret.setRestriction(w, "Chat", true)
    A.same({ secretNow(_G.C_EncounterTimeline.GetEventInfo, 1), secretNow(_G.C_Club.GetSubscribedClubs) }, { false, true })
  end)
end

local function test_secrecy_predicates_follow_the_restrictions_assumed() -- (C16)
  H.withCombat("retail", function(w)
    A.same(
      { _G.C_Secrets.HasSecretRestrictions(), _G.C_Secrets.ShouldAurasBeSecret(), _G.C_CombatLog.IsCombatLogRestricted() },
      { true, false, false }
    )
    Secret.setRestriction(w, "PvPMatch", true)
    A.same(
      { _G.C_Secrets.ShouldAurasBeSecret(), _G.C_Secrets.ShouldUnitIdentityBeSecret("party1"), _G.C_CombatLog.IsCombatLogRestricted() },
      { true, true, true }
    )
  end)
end

local function test_cleu_payload_is_secret_while_restricted_assumed() -- (C17)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local entry = Log.emit(w, "SPELL_DAMAGE", brute, ann, { spellID = H.SPELLS.STRIKE, amount = 40 })
    -- Retail has no payload accessor for addons (row C18), so give the world the name vanilla has to read one.
    w.globals.api.CombatLogGetCurrentEventInfo = true
    w:install("CombatLogGetCurrentEventInfo", function()
      return unpack(entry, 1, entry.n)
    end)
    local got = { asAddon(w, _G.CombatLogGetCurrentEventInfo) }
    A.eq(got[2], "SPELL_DAMAGE")
    A.eq(_G.issecretvalue(got[15]), false)
    Secret.setRestriction(w, "Combat", true)
    got = { asAddon(w, _G.CombatLogGetCurrentEventInfo) }
    local fields = { got[1] == entry[1], got[2], got[3], _G.issecretvalue(got[4]), _G.issecretvalue(got[15]) }
    A.same(fields, { true, "SPELL_DAMAGE", false, true, true }) -- hideCaster is a boolean, so it stays plain
    A.eq(Secret.reveal(got[15]), entry[15])
  end)
end

local function test_secret_install_is_retail_only()
  H.withCombat("vanilla", function(w)
    A.eq(w.isSecret, nil)
    A.eq(w.returnFilter, nil)
    A.eq(_G.issecretvalue(1), false)
  end)
end

local function test_snapshot_reveals_secret_text()
  H.withCombat("retail", function(w)
    local frame = _G.CreateFrame("Frame")
    local fs = frame:CreateFontString()
    local secret = Secret.make("Hidden", w)
    asAddon(w, fs.SetText, fs, secret)
    A.eq(fs:GetText(), secret) -- the addon keeps the secret as is
    local text
    A.eq(
      pcall(function()
        text = Snapshot.frame(frame)
      end),
      true
    )
    A.contains(text, "[ffffff]Hidden")
  end)
end

-- Measuring is kit work on the real text: a font string holding a secret sizes like the plain text it hides.
local function test_a_secret_text_measures_as_its_hidden_text()
  H.withCombat("retail", function(w)
    local frame = _G.CreateFrame("Frame")
    local plain, hidden = frame:CreateFontString(), frame:CreateFontString()
    plain:SetText("Hidden")
    asAddon(w, hidden.SetText, hidden, Secret.make("Hidden", w))
    local ok, width = pcall(hidden.GetStringWidth, hidden)
    A.same({ ok, width }, { true, plain:GetStringWidth() })
    A.eq(hidden:GetStringHeight(), plain:GetStringHeight())
    A.eq(hidden:GetUnboundedStringWidth(), plain:GetUnboundedStringWidth())
    A.eq(hidden:IsTruncated(), false)
  end)
end

-- The usual health bar: an addon feeds secret health into a StatusBar. It keeps the secret, and the render draws the fill.
local function test_a_status_bar_takes_secret_values_and_renders_them()
  H.withCombat("retail", function(w)
    local bar = _G.CreateFrame("StatusBar", "SecretBar", _G.UIParent)
    bar:SetSize(100, 10)
    bar:SetPoint("CENTER")
    local max, value = Secret.make(1000, w), Secret.make(400, w)
    A.eq(pcall(asAddon, w, bar.SetMinMaxValues, bar, 0, max), true)
    A.eq(pcall(asAddon, w, bar.SetValue, bar, value), true)
    A.eq(asAddon(w, bar.GetValue, bar), value)
    local widget = WidgetSnap.snap(w, "SecretBar").widget
    A.same({ widget.min, widget.max, widget.value }, { 0, 1000, 400 })
  end)
end

-- Lua 5.1 cannot raise on a truth test, so a secret boolean would always pass `if`: the kit hands addons the plain boolean.
local function test_a_boolean_return_stays_plain_in_combat_assumed() -- (C16)
  H.withCombat("retail", function(w, _, s)
    s:preset("dungeon", { inCombat = true })
    A.eq(_G.issecretvalue(asAddon(w, _G.UnitHealth, "party1")), true)
    local same = asAddon(w, _G.UnitIsUnit, "party2", "player")
    A.same({ type(same), same }, { "boolean", false })
  end)
end

-- The client takes a secret as an API argument: a kit implementation reads the value it hides.
local function test_a_secret_passed_back_to_an_api_is_read_as_its_value()
  H.withCombat("retail", function(w, _, s)
    s:preset("dungeon", { inCombat = true })
    local guid = asAddon(w, _G.UnitGUID, "party1")
    A.eq(_G.issecretvalue(guid), true)
    A.eq(Secret.reveal(asAddon(w, _G.UnitTokenFromGUID, guid)), "party1")
    A.eq(asAddon(w, _G.issecretvalue, guid), true) -- a reader still sees the secret
  end)
end

-- A w:stub is a fake of the client too: its byArgs key is the value a secret argument hides.
local function test_a_stub_reads_a_secret_argument_as_its_value()
  H.withCombat("retail", function(w, _, s)
    s:preset("dungeon", { inCombat = true })
    local guid = asAddon(w, _G.UnitGUID, "party1")
    w:stub("UnitTokenFromGUID", { byArgs = { [Secret.reveal(guid)] = { "stubbed" } } })
    A.eq(asAddon(w, _G.UnitTokenFromGUID, guid), "stubbed")
  end)
end

local function test_state_sets_combat_and_encounter_restrictions()
  H.withCombat("retail", function(w)
    local player = Actors.get(w, "player")
    local boss = Actors.add(w, { kind = "boss", name = "Boss", token = "boss1", hostile = true, health = 100 })
    State.engage(w, boss, player)
    A.same(
      { _G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Combat), _G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Encounter) },
      { true, true }
    )
    State.disengage(w, boss)
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Encounter), false)
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Combat), true) -- combat drops after the delay
    w:advance(w.combat.dropDelay + 0.1)
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Combat), false)
  end)
end

local function test_a_plain_npc_fight_sets_combat_but_not_encounter()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    State.engage(w, brute, Actors.get(w, "player"))
    A.same(
      { _G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Combat), _G.C_RestrictedActions.IsAddOnRestrictionActive(RESTRICTION.Encounter) },
      { true, false }
    )
  end)
end

return function()
  test_health_is_secret_for_addons_in_combat_only()
  test_restriction_events_and_api()
  test_secret_operations_error_in_addon_code_assumed()
  test_concatenation_and_truthiness_stay_allowed_assumed()
  test_engine_context_operates_on_the_real_value()
  test_non_secret_functions_stay_plain()
  test_when_conditions_follow_their_restriction_assumed()
  test_secrecy_predicates_follow_the_restrictions_assumed()
  test_cleu_payload_is_secret_while_restricted_assumed()
  test_secret_install_is_retail_only()
  test_snapshot_reveals_secret_text()
  test_a_secret_text_measures_as_its_hidden_text()
  test_a_status_bar_takes_secret_values_and_renders_them()
  test_a_boolean_return_stays_plain_in_combat_assumed()
  test_a_secret_passed_back_to_an_api_is_read_as_its_value()
  test_a_stub_reads_a_secret_argument_as_its_value()
  test_state_sets_combat_and_encounter_restrictions()
  test_a_plain_npc_fight_sets_combat_but_not_encounter()
end

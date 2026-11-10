-- SimProcs: the proc rules of the kit (spec 7.5) and the overlay glows they light. A rule { id, onEvent, every, aura?,
-- overlay, duration } is read from w.sim.procRules (Task 5.6 sets them). A landed swing ("swing_hit") or a dodge
-- ("dodge") counts for each rule of its event, and the rule fires on every `every`-th: the rule's aura goes on the player,
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(overlay) fires and the glow is armed to expire. Casting the overlay spell (which also
-- removes the aura), the expiry and the aura going all end the glow with GLOW_HIDE(overlay), once. The dodge is this
-- unit's too: it makes the player's swing at a SimMobs mob miss. State: w.sim.procs = { active = { [overlay] = { untilT,
-- auraInstanceID?, token } }, count = { [ruleIndex] = n }, swings = n }.
local M = {}

local Auras = require("combat_auras")
local Combat = require("combat")
local Resolve = require("combat_resolve")
local SimState = require("sim_state")
local State = require("game.state")
local define = State.define

local MS = 1000
local SHOW = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
local HIDE = "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"

-- source: assumed (no combat table; the glow, not the odds, is what the client shows) every fifth swing of the player at a
-- mob is dodged, so tests and the WASM host agree on the swing.
M.DODGE_EVERY = 5

-- The rules of the world: the list Task 5.6 set, or none.
function M.rules(w)
  return w.sim.procRules or {}
end

local function hide(w, overlay)
  local active = w.sim.procs.active
  if not active[overlay] then
    return
  end
  active[overlay] = nil
  Combat.fire(w, HIDE, overlay)
end

-- Arms the expiry of a glow. A timer that was armed for an earlier end (the glow was extended since) or for a glow that is
-- over does nothing.
local function arm(w, overlay, entry)
  local due = entry.untilT
  Combat.later(w, due - w.now, function()
    if w.sim.procs.active[overlay] == entry and entry.untilT == due then
      hide(w, overlay)
    end
  end)
end

-- The player's aura with instance id, or nil.
local function findAura(w, id)
  for _, aura in ipairs(w.sim.player.auras) do
    if aura.auraInstanceID == id then
      return aura
    end
  end

  return nil
end

local function addAura(w, rule)
  local player = w.sim.player
  local aura = Resolve.aura(w, player, player, { spellID = rule.aura, duration = rule.duration / MS })

  return aura.auraInstanceID
end

-- Puts the glow back to a full duration and keeps its aura running with it.
local function extend(w, rule, entry)
  local aura = findAura(w, entry.auraInstanceID)
  entry.untilT = w.now + rule.duration / MS
  if aura then
    Auras.refresh(w, w.sim.player, aura, rule.duration / MS)
  end
  arm(w, rule.overlay, entry)
end

-- source: assumed (spec 7.5) the aura goes on first, then the glow shows; a rule that fires again while its glow runs
-- extends the glow and the aura and shows nothing new.
function M.fire(w, rule)
  local active = w.sim.procs.active
  local running = active[rule.overlay]
  if running then
    extend(w, rule, running)

    return
  end
  local entry = { untilT = w.now + rule.duration / MS }
  active[rule.overlay] = entry
  entry.auraInstanceID = rule.aura and addAura(w, rule) or nil
  Combat.fire(w, SHOW, rule.overlay)
  arm(w, rule.overlay, entry)
end

-- source: assumed (Ruling 5.6-a) casting the overlay spell uses the proc up: its aura goes with the glow (the aura
-- listener hides the glow; hide covers a glow with no aura).
function M.consume(w, spellID)
  local entry = w.sim.procs.active[spellID]
  local aura = entry and findAura(w, entry.auraInstanceID)
  if aura then
    Auras.remove(w, w.sim.player, aura)
  end
  hide(w, spellID)
end

-- Counts one event for each rule of that kind; a rule fires on every every-th count.
-- grug: no RNG, so lupa/WASM parity and tests are exact
local function trigger(w, event)
  local count = w.sim.procs.count
  for index, rule in ipairs(M.rules(w)) do
    if rule.onEvent == event then
      count[index] = (count[index] or 0) + 1
      if count[index] % (rule.every or 1) == 0 then
        M.fire(w, rule)
      end
    end
  end
end

local function hasDodgeRule(w)
  for _, rule in ipairs(M.rules(w)) do
    if rule.onEvent == "dodge" then
      return true
    end
  end

  return false
end

-- A mob the player swings at can dodge; an actor that is no SimMobs mob, and a mob a test switched off, never does.
local function canDodge(target)
  return target.mobState ~= nil and not target.dodgeOff
end

-- source: assumed (no combat table; the glow, not the odds, is what the client shows) every DODGE_EVERY-th swing at a mob,
-- while a dodge rule exists, misses with DODGE and fires the rule.
local function dodge(w, spec)
  local procs = w.sim.procs
  procs.swings = procs.swings + 1
  if procs.swings % M.DODGE_EVERY == 0 then
    spec.miss = "DODGE"
    trigger(w, "dodge")
  end
end

-- The seams.swing function: the call before the damage may dodge, the one after a landed swing counts a hit.
local function onSwing(w, _attacker, target, spec)
  if spec.landed then
    trigger(w, "swing_hit")
  elseif canDodge(target) and hasDodgeRule(w) then
    dodge(w, spec)
  end
end

-- The glow of every overlay hides with its aura, in overlay order (a world reset is a fresh login: nothing stays lit).
function M.reset(w)
  local overlays = {}
  for overlay in pairs(w.sim.procs.active) do
    overlays[#overlays + 1] = overlay
  end
  table.sort(overlays)
  for _, overlay in ipairs(overlays) do
    M.consume(w, overlay)
  end
  w.sim.procs.count, w.sim.procs.swings = {}, 0
end

-- The glow of an aura that went is over. source: assumed (spec 7.5) an aura removal hides the glow it lit.
local function onAura(w, actor, update)
  if actor ~= w.sim.player then
    return
  end
  for _, id in ipairs(update.removedAuraInstanceIDs or {}) do
    for overlay, entry in pairs(w.sim.procs.active) do
      if entry.auraInstanceID == id then
        hide(w, overlay)
      end
    end
  end
end

-- Whether the aura the glow lit is still on the player (a glow with no aura has none to lose).
local function worn(w, entry)
  return not entry.auraInstanceID or findAura(w, entry.auraInstanceID) ~= nil
end

local function byOverlay(a, b)
  return a.overlay < b.overlay
end

local function export(w)
  local procs, glows = w.sim.procs, {}
  for overlay, entry in pairs(procs.active) do
    glows[#glows + 1] = { overlay = overlay, untilT = entry.untilT, auraInstanceID = entry.auraInstanceID }
  end
  table.sort(glows, byOverlay)

  return { active = glows, count = State.merge({}, procs.count), swings = procs.swings }
end

-- source: assumed (a reload keeps a glow) a glow comes back with the time it had left and its expiry is armed again, with
-- no event; the counts come back as they were. One whose time ran out, or whose aura did not come back, stays dark.
local function restore(w, data)
  local procs = w.sim.procs
  procs.count, procs.swings = State.merge({}, data.count), data.swings
  for _, glow in ipairs(data.active) do
    local entry = { untilT = glow.untilT, auraInstanceID = glow.auraInstanceID }
    if entry.untilT > w.now and worn(w, entry) then
      procs.active[glow.overlay] = entry
      arm(w, glow.overlay, entry)
    end
  end
end

local function onCast(w, caster, rec)
  if caster == w.sim.player then
    M.consume(w, rec.id)
  end
end

local function defineFakes(w)
  define(w, "C_SpellActivationOverlay.IsSpellOverlayed", function(spellID)
    return w.sim.procs.active[spellID] ~= nil
  end)
end

-- Adds the proc state, hangs the hit and the dodge on the swing seam and the consume on the cast seam, listens to the
-- aura, defines the overlay query and hooks the reset and the reload.
function M.install(w)
  w.sim.procs = { active = {}, count = {}, swings = 0 }
  table.insert(w.sim.seams.swing, onSwing)
  table.insert(w.sim.seams.cast, onCast)
  table.insert(w.sim.hooks.reset, M.reset)
  Combat.listen(w, "aura", function(actor, update)
    onAura(w, actor, update)
  end)
  defineFakes(w)
  SimState.persist(w, "procs", { export = export, restore = restore })
end

return M

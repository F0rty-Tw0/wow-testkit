-- AI: an actor's behaviour rules (actor.ai) run on the world clock and act through Resolve, so a rule's numbers are the
-- scenario's own (R4). Ai.start schedules each rule and holds its timer in actor.timers (rule -> timer); Ai.stop cancels
-- them. A swing or spell rule repeats every rule.every seconds from the start; a cooldown rule applies its aura once when the
-- health fraction falls below rule.below. The AI stops itself when the actor dies or despawns.
--
-- actor.ai = { swing = { every, damage, school? }, spells = { { spellID, every, castTime?, damage?, heal?, interruptible? } },
-- targets = "threat" | "random" (enemies), role = "tank" | "healer" | "dps" (a label), cooldowns = { { spellID, below, aura } } }
local M = {}

local Combat = require("combat")
local Resolve = require("combat_resolve")
local State = require("combat_state")
local Threat = require("combat_threat")

local unpack = unpack

local PLAYER = "player"
-- actor -> true while a cooldown check is queued; actor -> { rule -> true } for the cooldowns already fired.
local queued = setmetatable({}, { __mode = "k" })
local fired = setmetatable({}, { __mode = "k" })

-- The actors fighting this one on the other side that are alive, in spawn order.
local function livingFoes(w, actor)
  local out = {}
  for _, guid in ipairs(w.combat.order) do
    local other = w.combat.actors[guid]
    if actor.foes and actor.foes[guid] and other.isEnemy ~= actor.isEnemy and not other.isDead then
      out[#out + 1] = other
    end
  end
  return out
end

-- The living actor with the most threat on the enemy's list (the first listed among equals), or nil.
local function topThreat(enemy)
  local list, top = enemy.threatList, nil
  for _, source in ipairs(list and list.order or {}) do
    if not source.isDead and (not top or list.value[source.guid] > list.value[top.guid]) then
      top = source
    end
  end
  return top
end

-- Who a damage rule hits. An enemy takes the top-threat living target, else the first engaged foe; with targets = "random" it
-- takes the foe c.random(n) picks (math.random unless the scenario sets c.random). A friend takes its own living target,
-- else the first engaged foe.
local function damageTarget(w, actor)
  local foes = livingFoes(w, actor)
  if actor.isEnemy then
    if actor.ai.targets == "random" and #foes > 0 then
      return foes[(w.combat.random or math.random)(#foes)]
    end
    return topThreat(actor) or foes[1]
  end
  local own = actor.targetGuid and w.combat.actors[actor.targetGuid]
  if own and own.isEnemy and not own.isDead then
    return own
  end
  return foes[1]
end

-- The living ally (same side, itself included) with the lowest health fraction, nil when every ally is at full health.
local function healTarget(w, actor)
  local best, bestFraction = nil, 1
  for _, guid in ipairs(w.combat.order) do
    local ally = w.combat.actors[guid]
    local fraction = ally.healthMax > 0 and ally.health / ally.healthMax or 1
    if ally.isEnemy == actor.isEnemy and not ally.isDead and fraction < bestFraction then
      best, bestFraction = ally, fraction
    end
  end
  return best
end

local function swing(w, actor, rule)
  local target = damageTarget(w, actor)
  if target then
    Resolve.damage(w, actor, target, { amount = rule.damage, school = rule.school })
  end
end

local function cast(w, actor, rule)
  if actor.cast or actor.channel then
    return
  end
  local target
  if rule.heal then
    target = healTarget(w, actor)
  elseif rule.damage then
    target = damageTarget(w, actor)
  end
  if (rule.heal or rule.damage) and not target then
    return
  end
  Resolve.cast(w, actor, {
    spellID = rule.spellID,
    castTime = rule.castTime,
    target = target,
    notInterruptible = rule.interruptible == false,
    effect = function()
      if not target or target.isDead then
        return
      end
      if rule.damage then
        Resolve.damage(w, actor, target, { amount = rule.damage, spellID = rule.spellID })
      end
      if rule.heal then
        Resolve.heal(w, actor, target, { amount = rule.heal, spellID = rule.spellID })
      end
    end,
  })
end

-- Repeats act(w, actor, rule) every rule.every seconds. The next tick is armed first, so an action that raises does not
-- end the rule.
local function arm(w, actor, rule, act)
  if type(rule.every) ~= "number" or rule.every <= 0 then
    error("Ai.start: a rule's every must be a number above 0, got " .. tostring(rule.every), 3)
  end
  local function tick()
    if not actor.timers then
      return
    end
    if actor.isDead then
      M.stop(w, actor)
      return
    end
    actor.timers[rule] = Combat.later(w, rule.every, tick)
    act(w, actor, rule)
  end
  actor.timers[rule] = Combat.later(w, rule.every, tick)
end

local function checkCooldowns(w, actor)
  if not actor.timers or actor.isDead or actor.healthMax <= 0 then
    return
  end
  for _, rule in ipairs(actor.ai.cooldowns or {}) do
    if not fired[actor][rule] and actor.health / actor.healthMax < rule.below then
      fired[actor][rule] = true
      local spec = { spellID = rule.spellID }
      for key, value in pairs(rule.aura or {}) do
        spec[key] = value
      end
      Resolve.aura(w, actor, actor, spec)
    end
  end
end

local function queueCooldowns(w, actor)
  if queued[actor] then
    return
  end
  queued[actor] = true
  Combat.later(w, 0, function()
    queued[actor] = nil
    checkCooldowns(w, actor)
  end)
end

-- Schedules every rule of actor.ai; an actor without rules, one already started and a dead one are left alone.
function M.start(w, actor)
  local ai = actor.ai
  if not ai or actor.timers or actor.isDead then
    return
  end
  actor.timers = {}
  fired[actor] = {}
  if ai.swing then
    arm(w, actor, ai.swing, swing)
  end
  for _, rule in ipairs(ai.spells or {}) do
    arm(w, actor, rule, cast)
  end
  if ai.cooldowns then
    queueCooldowns(w, actor)
  end
end

function M.stop(_, actor)
  for _, timer in pairs(actor.timers or {}) do
    timer:Cancel()
  end
  actor.timers = nil
  fired[actor] = nil
end

-- The group's living tank pulls, else the player.
local function pullerOf(c, player)
  for _, member in ipairs(c.group and c.group.members or {}) do
    if member.role == "TANK" and not member.isDead then
      return member
    end
  end
  return player
end

-- Engages the enemy with the player and the player's group, puts the puller on the enemy's threat list (at 0, so it
-- leads until someone out-threats it), then starts the AI of every actor that has one.
function M.pull(w, enemy)
  local c = w.combat
  local player = w.unitState.byToken[PLAYER]
  State.engage(w, enemy, player)
  for _, member in ipairs(c.group and c.group.members or {}) do
    if member ~= player then
      State.engage(w, enemy, member)
    end
  end
  if enemy.isEnemy then
    Threat.add(w, enemy, pullerOf(c, player), 0)
  end
  for _, guid in ipairs({ unpack(c.order) }) do
    local actor = c.actors[guid]
    if actor then
      M.start(w, actor)
    end
  end
end

-- The AI ends with the actor, and a health change may cross a cooldown's threshold.
function M.install(w)
  local function stop(actor)
    M.stop(w, actor)
  end
  Combat.listen(w, "death", stop)
  Combat.listen(w, "despawn", stop)
  Combat.listen(w, "health", function(actor)
    if actor.timers and actor.ai.cooldowns then
      queueCooldowns(w, actor)
    end
  end)
end

return M

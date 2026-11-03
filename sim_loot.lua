-- SimLoot: what a killed hostile mob drops. actor.loot is its table { money = copper, items = { { itemID, count = 1,
-- chance = 1 } } }; false is no loot and nil is the default table. roll turns it into actor.drops (the coin first) and
-- actor.lootable; the window (SimLootWindow) opens and takes them. w.sim.loot = { seed, line, corpses, window? }.
local M = {}

local Actors = require("combat_actors")
local BlizzardData = require("blizzard_data")
local Combat = require("combat")
local GameState = require("game.state")
local SimLootWindow = require("sim_loot_window")
local SimState = require("sim_state")

-- The kit's two loot items: ids, names, quality and stack sizes are kit-authored (no extract needed).
M.KIT = { gray = 900201, white = 900202 }

local KIT_ITEMS = {
  [M.KIT.gray] = { name = "Kit Scrap", quality = 0, stackCount = 5, icon = M.KIT.gray },
  [M.KIT.white] = { name = "Kit Linen", quality = 1, stackCount = 20, icon = M.KIT.white },
}

-- The real items of the default table: Broken Fang (quality 0) and Linen Cloth (quality 1).
-- source: confirmed (both ids exist in the retail 70575 and tbc 70577 extracts' ItemSparse).
M.REAL = { gray = 7073, white = 2589 }

-- source: assumed (spec 8.1) a default mob drops 37 copper, one gray item and two white ones; the kit has no loot data.
M.DEFAULT_MONEY = 37

M.open, M.slot, M.close, M.canLoot = SimLootWindow.open, SimLootWindow.slot, SimLootWindow.close, SimLootWindow.canLoot

local MODULUS = 2147483647
local MULTIPLIER = 16807

-- The default table's two item ids, cached in w.sim.loot.items: the real ones when BlizzardData.items resolves both to
-- a named record, else the kit's.
-- source: assumed the kit items are the fallback so the suite never needs an extract.
function M.defaultItems(w)
  local state = w.sim.loot
  if state.items == nil then
    BlizzardData.items(w, { M.REAL.gray, M.REAL.white })
    local gray, white = w.mock.items[M.REAL.gray], w.mock.items[M.REAL.white]
    local resolved = gray and gray.name and white and white.name
    state.items = resolved and M.REAL or M.KIT
  end

  return state.items
end

function M.defaultTable(w)
  local items = M.defaultItems(w)

  return {
    money = M.DEFAULT_MONEY,
    items = { { itemID = items.gray, count = 1 }, { itemID = items.white, count = 2 } },
  }
end

-- The next draw in (0, 1): minstd (Park-Miller) over w.sim.loot.seed.
-- source: assumed (the real server rolls are not modelled; deterministic so lupa and the WASM worker agree, and the
-- product stays below 2^53). From seed 1 the draws are 7.8e-6, 0.1315, 0.7556.
local function draw(w)
  local state = w.sim.loot
  state.seed = (state.seed * MULTIPLIER) % MODULUS

  return state.seed / MODULUS
end

local function passes(w, entry)
  local chance = entry.chance
  if chance == nil or chance >= 1 then
    return true
  end

  return draw(w) < chance
end

local function rolledDrops(w, given)
  local drops = {}
  local copper = given.money or 0
  -- source: assumed the client lists the coin first (the classic LootFrame shows it as the first row).
  if copper > 0 then
    drops[#drops + 1] = { kind = "money", copper = copper }
  end
  for _, entry in ipairs(given.items or {}) do
    if passes(w, entry) then
      drops[#drops + 1] = { kind = "item", itemID = entry.itemID, count = entry.count or 1 }
    end
  end

  return drops
end

-- Builds actor.drops from actor.loot (nil is the default table, false is none) and registers the corpse.
function M.roll(w, actor)
  local given = actor.loot
  if given == nil then
    given = M.defaultTable(w)
  end
  actor.drops = given and rolledDrops(w, given) or {}
  actor.lootable = #actor.drops > 0
  w.sim.loot.corpses[actor.guid] = actor
end

-- source: assumed (spec 8.1) only a hostile mob drops loot: no roll for a player, a friend, or a party or raid member.
local function rollsOnDeath(actor)
  local grouped = actor.inParty or actor.inRaid

  return actor.isEnemy and not actor.isPlayer and not grouped and actor.drops == nil
end

local function copyDrops(drops)
  local out = {}
  for _, drop in ipairs(drops) do
    if not drop.taken then
      out[#out + 1] = { kind = drop.kind, copper = drop.copper, itemID = drop.itemID, count = drop.count }
    end
  end

  return out
end

-- The untaken drops of each corpse, sorted by guid; an open window is not saved (it closes silently on a reload).
local function export(w)
  local state, corpses = w.sim.loot, {}
  for guid, actor in pairs(state.corpses) do
    local drops = copyDrops(actor.drops)
    corpses[#corpses + 1] = { guid = guid, lootable = #drops > 0, drops = drops }
  end
  table.sort(corpses, function(a, b)
    return a.guid < b.guid
  end)

  return { seed = state.seed, line = state.line, corpses = corpses }
end

local function restore(w, data)
  local state = w.sim.loot
  state.seed, state.line = data.seed, data.line
  for _, row in ipairs(data.corpses) do
    local actor = Actors.get(w, row.guid)
    if actor then
      actor.drops, actor.lootable = row.drops, row.lootable
      state.corpses[row.guid] = actor
    end
  end
end

-- The reset hook: the chance sequence starts over.
function M.reset(w)
  w.sim.loot.seed = 1
end

local function rollOnDeath(w, actor)
  if rollsOnDeath(actor) then
    M.roll(w, actor)
  end
end

-- Puts the loot state, the kit items, the death roll, the corpse registry's despawn cleanup, the seed reset, the reload
-- state, the window and the loot action on the sim world.
function M.install(w)
  w.sim.loot = { seed = 1, line = 0, corpses = {} }
  for id, record in pairs(KIT_ITEMS) do
    w.mock.items[id] = w.mock.items[id] or GameState.merge({}, record)
  end
  Combat.listen(w, "death", function(actor)
    rollOnDeath(w, actor)
  end)
  Combat.listen(w, "despawn", function(actor)
    w.sim.loot.corpses[actor.guid] = nil
  end)
  SimState.persist(w, "loot", { export = export, restore = restore })
  SimLootWindow.install(w)
  table.insert(w.sim.hooks.reset, M.reset)
  w.sim.actions.loot = M.open
end

return M

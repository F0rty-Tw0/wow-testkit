-- Macro conditionals: SecureCmdOptionParse("[combat] fight; calm") picks the value of the first clause whose condition holds.
-- A clause is bracket groups followed by a value; a group is comma-separated conditions (AND) and an optional @unit, and a
-- clause holds when any of its groups does (OR) or when it has no brackets. Conditions read the mock (combat, modifiers,
-- group) and the unit fixtures; a name the kit does not model is false and counted in w.unscripted["macro:<name>"].
-- source: row TS17 (clause, group and `no` grammar; `@unit` and `target=unit`), the kit's code. Assumed there: OR between
-- bracket groups, slash alternatives after a colon, and [help] as exists and not canAttack (the kit has no UnitCanAssist).
local WorldApi = require("world_api")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

local API = { gate = "api" }
local DEFAULT_UNIT = "target"
local MODIFIERS = { shift = true, ctrl = true, alt = true }

local function trim(text)
  return text:match("^%s*(.-)%s*$")
end

local function parseItem(group, item)
  local unit = item:match("^@(.+)$") or item:match("^target=(.+)$")
  if unit then
    group.unit = trim(unit)

    return
  end
  local name, arg = item:match("^([^:]+):(.*)$")
  name = name or item
  local bare = name:lower():match("^no(.+)$")
  group[#group + 1] = { name = bare or name:lower(), arg = arg and arg:lower(), negate = bare ~= nil }
end

local function parseGroup(text)
  local group = {}
  for item in (text .. ","):gmatch("([^,]*),") do
    local trimmed = trim(item)
    if trimmed ~= "" then
      parseItem(group, trimmed)
    end
  end

  return group
end

-- A clause with an unterminated bracket is malformed: nil.
local function parseClause(text)
  local groups = {}
  local rest = trim(text)
  while rest:sub(1, 1) == "[" do
    local close = rest:find("]", 1, true)
    if not close then
      return nil
    end
    groups[#groups + 1] = parseGroup(rest:sub(2, close - 1))
    rest = trim(rest:sub(close + 1))
  end

  return { groups = groups, result = rest }
end

-- Clauses `{ { groups = { { { name, arg, negate }, ..., unit? }, ... }, result }, ... }` in order; blank clauses are skipped.
function M.parse(text)
  local clauses = {}
  for piece in (text .. ";"):gmatch("([^;]*);") do
    local clause = trim(piece) ~= "" and parseClause(piece)
    if clause then
      clauses[#clauses + 1] = clause
    end
  end

  return clauses
end

local function listHas(arg, wanted)
  for item in (arg .. "/"):gmatch("([^/]*)/") do
    if wanted(item) then
      return true
    end
  end

  return false
end

local function heldModifier(w, item)
  local held = w.mock.modifiers or {}

  return MODIFIERS[item] == true and held[item] == true
end

local function anyModifier(w)
  for name in pairs(MODIFIERS) do
    if heldModifier(w, name) then
      return true
    end
  end

  return false
end

local function canAttack(unit)
  return _G.UnitCanAttack("player", unit) == true
end

local function exists(unit)
  return _G.UnitExists(unit) == true
end

-- name -> function(w, arg, unit, opts) -> boolean
local CONDITIONS = {
  combat = function(w)
    return w.mock and w.mock.combat == true
  end,
  exists = function(_, _, unit)
    return exists(unit)
  end,
  harm = function(_, _, unit)
    return exists(unit) and canAttack(unit)
  end,
  help = function(_, _, unit)
    return exists(unit) and not canAttack(unit)
  end,
  dead = function(_, _, unit)
    return exists(unit) and _G.UnitIsDead(unit) == true
  end,
  mod = function(w, arg)
    if not arg then
      return anyModifier(w)
    end

    return listHas(arg, function(item)
      return heldModifier(w, item)
    end)
  end,
  group = function(w, arg)
    local kind = w.mock.group or "none"
    if not arg then
      return kind ~= "none"
    end

    return listHas(arg, function(item)
      return item == kind
    end)
  end,
  btn = function(_, arg, _, opts)
    local button = opts and opts.button
    if not arg then
      return button ~= nil
    end

    return button ~= nil and listHas(arg, function(item)
      return item == tostring(button)
    end)
  end,
}

local function answer(w, condition, unit, opts)
  local test = CONDITIONS[condition.name]
  if not test then
    WorldApi.markUnscripted(w, "macro:" .. condition.name)
  end
  local holds = test ~= nil and test(w, condition.arg, unit, opts) == true

  return holds ~= condition.negate
end

local function groupHolds(w, group, opts)
  local unit = group.unit or DEFAULT_UNIT
  for _, condition in ipairs(group) do
    if not answer(w, condition, unit, opts) then
      return false
    end
  end

  return true
end

-- The group that makes the clause hold, or nil. A clause without brackets holds through an empty group.
local function holdingGroup(w, clause, opts)
  if #clause.groups == 0 then
    return {}
  end
  for _, group in ipairs(clause.groups) do
    if groupHolds(w, group, opts) then
      return group
    end
  end

  return nil
end

local function evaluate(w, text, opts)
  for _, clause in ipairs(M.parse(text)) do
    local group = holdingGroup(w, clause, opts)
    if group then
      return clause.result, group.unit
    end
  end

  return nil
end

-- result, target of the first clause of text that holds (the target only when the group named one); nothing when none does.
-- opts.button is the clicked mouse button for [btn]. Runs as kit code, so the unit answers it reads are not the caller's calls.
function M.eval(w, text, opts)
  return w:run("blizzard", evaluate, w, text, opts)
end

function M.install(w)
  w:install("SecureCmdOptionParse", function(text)
    if type(text) == "string" then
      return M.eval(w, text)
    end
  end, API)
end

return M

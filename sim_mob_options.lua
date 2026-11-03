-- SimMobOptions: the checks on a mob's spawn options. SimMobs.spawn and pack run check before they add anything, so a refused
-- mob leaves no actor behind; the rules for a repeating AI rule are combat_ai's own (Ai.ruleError).
local M = {}

local Ai = require("combat_ai")

local OPTION_TYPES = { name = "string", level = "number", health = "number", hostile = "boolean" }
local POSITIVE = { "level", "health" }

-- Level 0: no file position, so the message reads the same through a script, a scenario and the session's reply.
local function fail(fmt, ...)
  error(string.format("SimMobs.spawn: " .. fmt, ...), 0)
end

local function validPos(pos)
  return type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
end

-- Raises for a repeating rule (ai.swing, or one of ai.spells) that Ai.start would refuse or run into later.
local function checkRule(rule, name)
  if type(rule) ~= "table" then
    fail("%s must be a table", name)
  end
  local problem = Ai.ruleError(rule)
  if problem then
    fail("%s: %s", name, problem)
  end
end

local function checkAi(ai)
  if ai == nil or ai == false then
    return
  end
  if type(ai) ~= "table" then
    fail("ai must be a table or false")
  end
  if ai.swing ~= nil then
    checkRule(ai.swing, "ai.swing")
    if type(ai.swing.damage) ~= "number" then
      fail("ai.swing.damage must be a number")
    end
  end
  for index, rule in ipairs(ai.spells or {}) do
    checkRule(rule, "ai.spells[" .. index .. "]")
  end
end

-- Raises "SimMobs.spawn: <field> must be a <type>" (or an above-0 number for level and health, or a runnable ai) for a bad
-- option.
function M.check(opts)
  for field, kind in pairs(OPTION_TYPES) do
    local value = opts[field]
    local wrongType = value ~= nil and type(value) ~= kind
    if wrongType then
      fail("%s must be a %s", field, kind)
    end
  end
  for _, field in ipairs(POSITIVE) do
    local value = opts[field]
    if value ~= nil and value <= 0 then
      fail("%s must be a number above 0", field)
    end
  end
  local badPos = opts.pos ~= nil and not validPos(opts.pos)
  if badPos then
    fail("pos must be a table with a number x and y")
  end
  checkAi(opts.ai)
end

return M

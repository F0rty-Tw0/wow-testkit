-- Shared pieces of the game-state fakes: the w.mock merge rules and Game.define, which installs a kit
-- implementation where the flavor's API data has the name (or where the caller lists the flavor).
local M = {}

local Flavors = require("tools.flavors")

-- The FrameXML names every flavor has (globals.framexml): pass as define's flavors argument.
M.ALL = Flavors.list

local API_GATE = { gate = "api" }

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

-- Merges patch into target key by key; a table value merges into an existing table, any other value replaces. Table
-- values are copied, so a later merge never writes into the caller's table.
function M.merge(target, patch)
  for key, value in pairs(patch) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      M.merge(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

-- Copies each default into target unless target already has that key; nested tables fill key by key.
function M.fill(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) ~= "table" then
      if target[key] == nil then
        target[key] = value
      end
    else
      if target[key] == nil then
        target[key] = {}
      end
      if type(target[key]) == "table" then
        M.fill(target[key], value)
      end
    end
  end
end

-- Installs impl as a kit implementation of name (call counting, validation and w:stub apply where the data has the
-- name). A name the flavor's data lacks is installed only when flavors lists the flavor (the rows of
-- docs/client-sources.md G1). Returns whether it was installed.
function M.define(w, name, impl, flavors)
  if w:passesGate(name, API_GATE) or (flavors ~= nil and contains(flavors, w.flavor)) then
    return w:install(name, impl)
  end
  return false
end

return M

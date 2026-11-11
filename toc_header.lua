-- An addon's own TOC header: which game types it loads on.
local M = {}

local Flavors = require("tools.flavors")
local Toc = require("toc")

local GAME_TYPE_HEADER = "AllowLoadGameType"

-- source: assumed (row BU8) the `## AllowLoadGameType:` header lists the game types the addon loads on, read as the
-- per-file directive is (Toc.allowedOn, row L1).
local function gameTypeAllows(meta, row)
  local value = meta[GAME_TYPE_HEADER]
  if not value then
    return true
  end
  local gameTypes = {}
  for name in value:gmatch("[^,%s]+") do
    gameTypes[name:lower()] = true
  end
  return Toc.allowedOn({ path = "", directives = { [GAME_TYPE_HEADER] = gameTypes } }, row, {})
end

-- source: confirmed (row BU26) `## AllowLoad: Glue` keeps the addon out of the game UI; Game and Both let it in. A
-- trailing `[AllowLoadGameType ...]` limits the directive to those game types (assumed); an unknown value loads.
local function environmentAllows(meta, row)
  local value = meta.AllowLoad
  if not value then
    return true
  end
  local line = Toc.parseFileLine(value)
  return not Toc.allowedOn(line, row, {}) or line.path:lower() ~= "glue"
end

-- true when the addon loads in flavor's game UI; else false and the reason: "game type" or "glue screen".
function M.loadsOn(meta, flavor)
  local row = Flavors.get(flavor)
  if not gameTypeAllows(meta, row) then
    return false, "game type"
  elseif not environmentAllows(meta, row) then
    return false, "glue screen"
  end
  return true
end

return M

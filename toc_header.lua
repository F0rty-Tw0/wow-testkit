-- An addon's own TOC header: which game types it loads on.
local M = {}

local Flavors = require("tools.flavors")
local Toc = require("toc")

local GAME_TYPE_HEADER = "AllowLoadGameType"

-- source: assumed (row BU8) the `## AllowLoadGameType:` header lists the game types the addon loads on, read as the
-- per-file directive is (Toc.allowedOn, row L1); false when the flavor is outside the list.
function M.loadsOn(meta, flavor)
  local value = meta[GAME_TYPE_HEADER]
  if not value then
    return true
  end
  local gameTypes = {}
  for name in value:gmatch("[^,%s]+") do
    gameTypes[name:lower()] = true
  end
  return Toc.allowedOn({ path = "", directives = { [GAME_TYPE_HEADER] = gameTypes } }, Flavors.get(flavor), {})
end

return M

-- The five game flavors the kit loads addons on, with their source branches, TOC keys and build versions.
local M = {}

M.WOW_PROJECT = {
  WOW_PROJECT_MAINLINE = 1,
  WOW_PROJECT_CLASSIC = 2,
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
  WOW_PROJECT_MISTS_CLASSIC = 19,
}

M.list = { "retail", "mists", "vanilla", "tbc", "forever" }

local P = M.WOW_PROJECT

-- interfaceKeys / tocSuffixes are in priority order: the first match wins.
local ROWS = {
  retail = {
    branch = "live",
    product = "wow",
    projectId = P.WOW_PROJECT_MAINLINE,
    gameTypes = { standard = true, mainline = true },
    interfaceKeys = { "Interface-Mainline" },
    tocSuffixes = { "_Standard", "_Mainline" },
    version = "12.1.0.69933",
  },
  forever = {
    branch = "forever",
    product = nil,
    projectId = P.WOW_PROJECT_MAINLINE,
    -- warcraft.wiki.gg TOC_format: game type camelot with the alias forever, TOC suffix _Camelot with the alias _Forever.
    gameTypes = { camelot = true, forever = true, mainline = true },
    interfaceKeys = { "Interface-Forever" },
    tocSuffixes = { "_Camelot", "_Forever", "_Mainline" },
    version = "1.60.1.70205",
  },
  mists = {
    branch = "classic",
    product = "wow_classic",
    projectId = P.WOW_PROJECT_MISTS_CLASSIC,
    gameTypes = { mists = true, classic = true },
    interfaceKeys = { "Interface-Mists", "Interface-MoP" },
    tocSuffixes = { "_Mists", "_Classic" },
    version = "5.5.4.70032",
  },
  vanilla = {
    branch = "classic_era",
    product = "wow_classic_era",
    projectId = P.WOW_PROJECT_CLASSIC,
    gameTypes = { vanilla = true, classic = true },
    interfaceKeys = { "Interface-Vanilla", "Interface-Classic" },
    tocSuffixes = { "_Vanilla", "_Classic" },
    version = "1.15.9.70003",
  },
  tbc = {
    branch = "classic_anniversary",
    product = "wow_anniversary",
    projectId = P.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,
    gameTypes = { tbc = true, classic = true },
    interfaceKeys = { "Interface-TBC", "Interface-BCC" },
    tocSuffixes = { "_TBC", "-BCC", "_Classic" },
    version = "2.5.6.69795",
  },
}

-- "12.1.0.69933" -> 120100
function M.tocVersionOf(version)
  local major, minor, patch = string.match(version, "^(%d+)%.(%d+)%.(%d+)")
  if not major then
    error("not a game version: " .. tostring(version), 2)
  end
  return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

-- 120100 -> 1201
function M.majorMinorOf(tocVersion)
  return math.floor(tocVersion / 100)
end

-- path with each [Family] and [Game] variable of a TOC file line expanded for flavor; another [Variable] stays as written.
-- source: confirmed (row BU3) wiki TOC_format, [Family] "Mainline, or Classic", [Game] "Standard, Vanilla, Camelot, TBC,
-- Wrath, or Mists": the family is the flavor's last TOC suffix, the game its first (Standard, Camelot, Mists, Vanilla, TBC).
function M.expandTocPath(name, path)
  local suffixes = M.get(name).tocSuffixes
  local folders = { family = suffixes[#suffixes], game = suffixes[1] }
  return (path:gsub("%[(%a+)%]", function(token)
    local suffix = folders[token:lower()]
    return suffix and (suffix:gsub("^[_%-]", ""))
  end))
end

local function setVersion(row, version)
  row.version = version
  row.tocVersion = M.tocVersionOf(version)
  row.majorMinor = M.majorMinorOf(row.tocVersion)
end

function M.get(name)
  local row = ROWS[name]
  if not row then
    error("unknown flavor '" .. tostring(name) .. "'; valid: " .. table.concat(M.list, ", "), 2)
  end
  return row
end

-- versions: { [flavor] = { version = "12.1.0.69933", mirrorCommit = "...", kethoCommit = "..." } } (api/versions.lua).
function M.load(versions)
  for name, entry in pairs(versions) do
    setVersion(M.get(name), entry.version)
  end
end

for name, row in pairs(ROWS) do
  row.name = name
  setVersion(row, row.version)
end

return M

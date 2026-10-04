-- Loads a flavor's split API manifest (api/<flavor>/init.lua index + one module per doc file + globals.lua)
-- and merges it into one table.
local M = {}

local Flavors = require("tools.flavors")

M.SECTIONS = { "functions", "events", "enums", "constants", "structs", "widgets" }

local cache = {}

function M.empty()
  local manifest = {}
  for _, section in ipairs(M.SECTIONS) do
    manifest[section] = {}
  end
  return manifest
end

-- Copies every entry of part's sections into manifest; a missing section in part is skipped.
function M.merge(manifest, part)
  for _, section in ipairs(M.SECTIONS) do
    for key, value in pairs(part[section] or {}) do
      manifest[section][key] = value
    end
  end
end

local function requireLoader(flavor)
  Flavors.get(flavor)
  local prefix = "api." .. flavor
  return function(name)
    return require(name and (prefix .. "." .. name) or prefix)
  end
end

local function fileLoader(root, flavor)
  local dir = root .. "/api/" .. flavor .. "/"
  return function(name)
    return assert(loadfile(dir .. (name or "init") .. ".lua"))()
  end
end

local function loadWith(loadPart)
  local index = loadPart(nil)
  local manifest = M.empty()
  for key, value in pairs(index) do
    manifest[key] = value
  end
  for _, file in ipairs(index.files) do
    M.merge(manifest, loadPart(file))
  end
  return manifest, loadPart("globals")
end

-- opts.root: load <root>/api/<flavor>/ by path (no flavor check); else require("api.<flavor>").
function M.load(flavor, opts)
  local root = opts and opts.root
  local key = (root or "") .. "\0" .. flavor
  local hit = cache[key]
  if hit then
    return hit.manifest, hit.globals
  end
  local loadPart = root and fileLoader(root, flavor) or requireLoader(flavor)
  local manifest, globals = loadWith(loadPart)
  cache[key] = { manifest = manifest, globals = globals }
  return manifest, globals
end

return M

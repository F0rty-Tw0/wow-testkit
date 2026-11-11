-- File modules (row L9): a Lua file an addon loads may return a value, its module, which `import(path)` answers. A path
-- that starts with "." names a file from the importing file's folder ("." between folders, no extension); any other path
-- starts with an addon name ("Blizzard_GamepadSmartNavigation.SecureHelper"). Names match ignoring case, as the
-- client's file lookups do.
local M = {}

local ADDON_CHUNK = "^@?addon:([^/]+)/(.*)$"

-- The module key of addon's file relative: "<addon>.<path without .lua, folders joined by '.'>", lower case.
local function moduleKey(addon, relative)
  local path = relative:gsub("%.[Ll][Uu][Aa]$", ""):gsub("[/\\]", ".")
  return (addon .. "." .. path):lower()
end

-- Records what addon's file relative returned when it loaded; a file that returns nothing records nothing.
function M.record(w, addon, relative, value)
  if value ~= nil then
    w.modules = w.modules or {}
    w.modules[moduleKey(addon, relative)] = value
  end
end

-- The source of the nearest addon chunk on the stack, or nil.
local function callerSource()
  for level = 3, 12 do
    local info = debug.getinfo(level, "S")
    if not info then
      return nil
    end
    if info.source:match(ADDON_CHUNK) then
      return info.source
    end
  end
end

-- source: assumed (row L9) a module not loaded yet, or never returned, is an error naming the path.
function M.import(w, path)
  local key
  if path:sub(1, 1) == "." then
    local addon, file = (callerSource() or ""):match(ADDON_CHUNK)
    local dir = file and file:match("^(.*)[/\\][^/\\]*$")
    key = moduleKey(addon or "", (dir and dir .. "/" or "") .. path:sub(2))
  else
    key = path:lower()
  end
  local value = w.modules and w.modules[key]
  if value == nil then
    error("import: no module '" .. path .. "'", 2)
  end
  return value
end

return M

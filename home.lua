-- Locates the kit's per-user cache directory (downloaded API dumps and similar).
local M = {}

local APP_DIR = "wow-testkit"

local function slashes(path)
  return (path:gsub("\\", "/"))
end

-- TESTKIT_HOME, else <LOCALAPPDATA>/wow-testkit (Windows), else <HOME>/.cache/wow-testkit.
function M.dir(getenv)
  getenv = getenv or os.getenv
  local explicit = getenv("TESTKIT_HOME")
  if explicit then
    return slashes(explicit)
  end
  local localAppData = getenv("LOCALAPPDATA")
  if localAppData then
    return slashes(localAppData) .. "/" .. APP_DIR
  end
  local home = getenv("HOME")
  if home then
    return slashes(home) .. "/.cache/" .. APP_DIR
  end
  error("cannot locate the wow-testkit home: set TESTKIT_HOME (or LOCALAPPDATA / HOME)", 2)
end

function M.path(...)
  return table.concat({ M.dir(), ... }, "/")
end

return M

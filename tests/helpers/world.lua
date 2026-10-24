-- Shared World test helpers. withWorld always destroys its world, so one failing test cannot leave a world
-- active and cascade "another world is active" into the rest.
local World = require("world")

local M = {}

-- opts: extra World.new options (screen).
function M.withWorld(flavor, fn, opts)
  local w = World.new({ flavor = flavor, screen = opts and opts.screen })
  local ok, err = pcall(fn, w)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- Resolves a dotted global name ("C_Timer.After"), or nil when any part is missing.
function M.lookup(name)
  local value = _G
  for part in name:gmatch("[^.]+") do
    value = type(value) == "table" and value[part] or nil
  end
  return value
end

return M

-- Lazy Blizzard frame names: reading a name from Ketho's Frames list (w.globals.frames) that nothing installed
-- creates an inert frame under that name, once, counted in w.unscripted["frame:<Name>"]. The widget type is a plain
-- Frame unless LAZY_TYPES names another. Other missing names fall through to _G's previous __index. World snapshots
-- _G's metatable, so destroy undoes this.
local M = {}

local WorldApi = require("world_api")

-- First match wins. Row F6: the edit box of each chat frame (floatingchatframe.xml:540); the template and the parent
-- are not modelled.
local LAZY_TYPES = { { "^ChatFrame%d+EditBox$", "EditBox" } }

local function previousLookup(previous, t, key)
  if type(previous) == "function" then
    return previous(t, key)
  elseif previous ~= nil then
    return previous[key]
  end
  return nil
end

local function lazyType(key)
  for _, entry in ipairs(LAZY_TYPES) do
    if key:match(entry[1]) then
      return entry[2]
    end
  end

  return "Frame"
end

local function lazyIndex(w, previous)
  return function(t, key)
    if type(key) == "string" and w.globals.frames[key] then
      local frame = w.ui.create(lazyType(key), key, nil)
      WorldApi.markUnscripted(w, "frame:" .. key)
      return frame
    end
    return previousLookup(previous, t, key)
  end
end

-- Sets a copy of _G's metatable (never mutating the snapshotted one) with the lazy __index.
function M.install(w)
  local current = debug.getmetatable(_G)
  local mt = {}
  for k, v in pairs(current or {}) do
    mt[k] = v
  end
  mt.__index = lazyIndex(w, current and current.__index)
  debug.setmetatable(_G, mt)
end

return M

-- Lazy Blizzard frame names: reading a name from Ketho's Frames list (w.globals.frames) that nothing installed
-- creates an inert frame under that name, once, counted in w.unscripted["frame:<Name>"]. The widget type is a plain
-- Frame unless LAZY_TYPES names another. Other missing names fall through to _G's previous __index. World snapshots
-- _G's metatable, so destroy undoes this.
-- source: assumed (row F9) with the Blizzard UI layer loaded (w.blizzard) no lazy frame is made: a lazy name there is an
-- addon the layer did not load, the client has no frame at all under it, and Blizzard's `if Frame then Frame:Method()`
-- guards must see nil (a stand-in passed them and crashed, e.g. FramerateFrame:UpdatePosition). Without the layer every
-- core frame (PlayerFrame, ChatFrame1) is lazy, and the client always has and shows those, so the frame stays shown.
-- The layer on with no extract (w.blizzard set, w.client nil) loads nothing, so it counts as no layer.
local M = {}

local WorldApi = require("world_api")

-- First match wins. Row F6: the edit box of each chat frame (floatingchatframe.xml:540); row F8: the chat frames
-- themselves (floatingchatframe.xml:698-751). The templates and the parents are not modelled.
local LAZY_TYPES = { { "^ChatFrame%d+EditBox$", "EditBox" }, { "^ChatFrame%d+$", "ScrollingMessageFrame" } }

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
    if type(key) == "string" and w.globals.frames[key] and not (w.blizzard and w.client) then
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

-- Render test helpers: a retail world with widgets and the stage-1 fakes on a 1920x1080 screen at UI scale 1 (so 1 UI
-- unit is 1 pixel), always destroyed, plus readers for a snapshot's items.
local HF = require("tests.helpers.framexml")

local M = {}

local SCREEN = { width = 1920, height = 1080 }

function M.withRender(fn)
  HF.withFrameXML("retail", fn, { screen = SCREEN })
end

-- The names of the items starting with prefix, in draw order (unnamed items have none).
function M.names(snap, prefix)
  local names = {}
  for _, item in ipairs(snap.items) do
    if item.name and item.name:sub(1, #prefix) == prefix then
      names[#names + 1] = item.name
    end
  end
  return names
end

-- The item called name, or nil when the snapshot has none.
function M.item(snap, name)
  for _, item in ipairs(snap.items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

-- The backdrop piece ("center" or "edge") of the frame called frameName, or nil when it has none.
function M.piece(snap, frameName, piece)
  local frame = M.item(snap, frameName)
  for _, item in ipairs(snap.items) do
    if item.kind == "backdrop" and item.parent == frame.id and item.piece == piece then
      return item
    end
  end
  return nil
end

-- { x, y, width, height } of the item called name.
function M.rect(snap, name)
  local item = M.item(snap, name)
  assert(item, "no item named " .. name)
  return item.rect
end

return M

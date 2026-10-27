-- Widget snapshot helpers for render tests: a widget centred on UIParent, and its snapshot item.
local H = require("tests.helpers.render")
local Render = require("render")

local M = {}

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 100, 50

-- A kind widget under UIParent at CENTER, so on the retail 1920x1080 render world its rect is
-- { x = 910, y = 515, width = 100, height = 50 } with the default size.
function M.anchored(kind, name, template, width, height)
  local frame = _G.CreateFrame(kind, name, _G.UIParent, template)
  frame:SetSize(width or DEFAULT_WIDTH, height or DEFAULT_HEIGHT)
  frame:SetPoint("CENTER")

  return frame
end

-- The snapshot item called name in world w.
function M.snap(w, name)
  local snapshot = Render.snapshot(w)

  return H.item(snapshot, name)
end

return M

-- The LuaCurveObject C_CurveUtil.CreateCurve hands out: points sorted by x, evaluated linearly or as steps. Blizzard's
-- CurveConstants.lua builds four at load; the kit draws nothing from them, so Cosine and Cubic evaluate as Linear.
local M = {}

local Curve = {}
Curve.__index = Curve

local LINEAR, STEP = 0, 1

function M.new()
  return setmetatable({ points = {}, curveType = LINEAR }, Curve)
end

function Curve:AddPoint(x, y)
  local points = self.points
  points[#points + 1] = { x = x, y = y }
  table.sort(points, function(a, b)
    return a.x < b.x
  end)
end

function Curve:ClearPoints()
  self.points = {}
end

function Curve:GetPointCount()
  return #self.points
end

function Curve:SetType(curveType)
  self.curveType = curveType
end

function Curve:GetType()
  return self.curveType
end

-- source: assumed (row G21) 0 with no points, the end points' y outside them, the previous point's y for Step.
function Curve:Evaluate(x)
  local points = self.points
  local first, last = points[1], points[#points]
  if not first then
    return 0
  elseif x <= first.x then
    return first.y
  elseif x >= last.x then
    return last.y
  end
  for i = 2, #points do
    local low, high = points[i - 1], points[i]
    if x < high.x then
      return self.curveType == STEP and low.y or low.y + (high.y - low.y) * (x - low.x) / (high.x - low.x)
    end
  end
  return last.y
end

return M

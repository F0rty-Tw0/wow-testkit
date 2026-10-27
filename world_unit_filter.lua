-- Unit filters for RegisterUnitEvent: a frame registered for units receives the event only when its first argument is
-- one of them. Mixed into the World methods by world_events.lua; the filters live in w.unitFilters[frame][event].
local M = {}

local methods = {}
M.methods = methods

-- units: the list of unit tokens the frame wants for event; an empty list removes the filter.
function methods:setUnitFilter(frame, event, units)
  if #units == 0 then
    self:clearUnitFilter(frame, event)
    return
  end
  local wanted = {}
  for _, unit in ipairs(units) do
    wanted[type(unit) == "string" and unit:lower() or unit] = true
  end
  local byEvent = self.unitFilters[frame] or {}
  self.unitFilters[frame] = byEvent
  byEvent[event] = wanted
end

function methods:clearUnitFilter(frame, event)
  local byEvent = self.unitFilters[frame]
  if byEvent then
    byEvent[event] = nil
  end
end

-- True when the frame has no filter for event or the filter lists unit.
function methods:passesUnitFilter(frame, event, unit)
  local byEvent = self.unitFilters[frame]
  local wanted = byEvent and byEvent[event]
  if not wanted then
    return true
  end
  return wanted[type(unit) == "string" and unit:lower() or unit] == true
end

return M

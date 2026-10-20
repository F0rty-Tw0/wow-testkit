-- GameTooltip:GetUnit and when the tooltip forgets its unit. Mainline flavors (those with TooltipDataProcessor,
-- w.tooltipCallbacks) follow Blizzard's Lua; Classic flavors model the C method. tip is the tooltip's state
-- (st.tooltip in framexml/fakes/tooltip.lua): tip.unit is the SetUnit token, tip.data the shown tooltip data.
local M = {}

local TooltipLines = require("framexml.fakes.tooltip_lines")

local TOOLTIP_NAME = "GameTooltip"
local HIDERS = { "Hide", "SetShown" }

-- source: Mainline GameTooltipDataMixin:GetUnit → TooltipUtil.GetDisplayedUnit (Blizzard_SharedXMLGame/Tooltip/
-- TooltipUtil.lua:34-41, live and forever): the unit token comes from the shown data's GUID, not from SetUnit.
local function displayedUnit(w, tip)
  local data = tip.data
  if not data then
    return
  end
  local guid = data.guid
  local unit = guid and TooltipLines.ask(w, "UnitTokenFromGUID", guid)
  local name = unit and (TooltipLines.ask(w, "UnitName", unit))

  return name, unit, guid
end

-- Mainline: name, unit, guid (rows T2, T3); Classic's C method: name, unit (wiki API_GameTooltip_GetUnit).
function M.get(w, tip)
  if w.tooltipCallbacks then
    return displayedUnit(w, tip)
  end
  if tip.unit ~= nil then
    return (TooltipLines.ask(w, "UnitName", tip.unit)), tip.unit
  end
end

local function forget(tip)
  tip.unit, tip.data = nil, nil
end

-- source: confirmed (row T3) GameTooltipTemplate's OnHide is GameTooltip_OnHide (Mainline GameTooltip.xml:27), whose
-- ClearHandlerInfo (GameTooltip.lua:421 live, :430 forever) drops the shown data; an addon's SetScript replaces it.
local function forgetOnMainlineHide(w, tooltip, tipOf)
  w:setScript(tooltip, "OnHide", function(self)
    forget(tipOf(w, self, TOOLTIP_NAME .. ":OnHide"))
  end)
end

-- source: assumed (row T3, user decision) wiki API_GameTooltip_GetUnit "Returns nil when the tooltip is not shown":
-- Classic forgets the unit when its own Hide or SetShown takes a shown tooltip to hidden, whatever its scripts are; a
-- tooltip never shown since SetUnit still answers.
local function forgetOnClassicHide(w, tooltip, tipOf)
  local index = getmetatable(tooltip).__index
  for _, name in ipairs(HIDERS) do
    local original = index[name]
    local label = TOOLTIP_NAME .. ":" .. name
    index[name] = function(self, ...)
      local wasShown = self:IsShown()
      original(self, ...)
      if wasShown and not self:IsShown() then
        forget(tipOf(w, self, label))
      end
    end
  end
end

-- tipOf(w, self, label) -> tip, from framexml/fakes/tooltip.lua.
function M.install(w, tooltip, tipOf)
  if w.tooltipCallbacks then
    forgetOnMainlineHide(w, tooltip, tipOf)
  else
    forgetOnClassicHide(w, tooltip, tipOf)
  end
end

return M

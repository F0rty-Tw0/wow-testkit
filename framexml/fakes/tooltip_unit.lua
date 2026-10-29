-- GameTooltip:GetUnit and when the tooltip forgets its unit. Mainline flavors (those with TooltipDataProcessor,
-- w.tooltipCallbacks) follow Blizzard's Lua; Classic flavors model the C method. tip is the tooltip's state
-- (st.tooltip in framexml/fakes/tooltip.lua): tip.unit is the SetUnit token, tip.data the shown tooltip data.
local M = {}

local Behaviour = require("ui.behaviour")
local TooltipLines = require("framexml.fakes.tooltip_lines")

local TOOLTIP_NAME = "GameTooltip"
local HIDERS = { "Hide", "SetShown" }
-- Ketho's FrameXML list decides which flavors get GameTooltip_OnHide (every flavor's lists it).
local KETHO_GATE = { gate = "framexml", flavors = {} }

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
-- GameTooltip inherits the template (:249); a CreateFrame with the template gets it from ui/templates.lua.
local function forgetOnMainlineHide(w, tooltip, tipOf)
  local label = "GameTooltip_OnHide"
  local function onHide(self)
    forget(tipOf(w, self, label))
  end
  w:install(label, onHide, KETHO_GATE)
  w:setScript(tooltip, "OnHide", onHide)
end

-- source: assumed (row T3, user decision) wiki API_GameTooltip_GetUnit "Returns nil when the tooltip is not shown":
-- Classic forgets the unit when its own Hide or SetShown takes a shown tooltip to hidden, or when it stops being
-- visible because an ancestor hid (the kit fires its OnHide then), whatever its scripts are; a tooltip never shown
-- since SetUnit still answers.
local function forgetOnClassicHide(w, tooltip, tipOf)
  local hideLabel = TOOLTIP_NAME .. ":OnHide"
  Behaviour.afterVisibility(w, TOOLTIP_NAME, function(self, script)
    -- An OnHide script that shows the tooltip again leaves it visible: no hide, as for the wrappers below.
    if script == "OnHide" and not self:IsVisible() then
      forget(tipOf(w, self, hideLabel))
    end
  end)
  local index = getmetatable(tooltip).__index
  for _, name in ipairs(HIDERS) do
    local original = index[name]
    local label = TOOLTIP_NAME .. ":" .. name
    index[name] = function(self, ...)
      -- tipOf raises the kit's "self is not a widget" error at the caller's line; a tail call to original can't, as
      -- Lua 5.1 reports the (tail call) frame, which has no line.
      local tip = tipOf(w, self, label)
      local wasShown = self:IsShown()
      original(self, ...)
      if wasShown and not self:IsShown() then
        forget(tip)
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

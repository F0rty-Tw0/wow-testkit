-- Scenario for the MotLike fixture and the real MouseOverTooltip: the default screen (UI scale 1), Minimap centred on
-- UIParent (the kit's Minimap has no anchors), a hovered player, and a preview-only GameTooltip layout.
-- The layout is not the client's: Task 6.7 replaces it.
local TOOLTIP_WIDTH = 220
local TOOLTIP_PADDING = 20
local LINE_HEIGHT = 14
local TEXT_INSET = 10

local function layoutTooltip()
  local tooltip = _G.GameTooltip
  local lines = tooltip:NumLines()
  tooltip:SetFrameStrata("TOOLTIP")
  tooltip:SetSize(TOOLTIP_WIDTH, TOOLTIP_PADDING + LINE_HEIGHT * lines)
  for i = 1, lines do
    local text = _G["GameTooltipTextLeft" .. i]
    text:SetFontObject("GameTooltipText")
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", tooltip, "TOPLEFT", TEXT_INSET, -TEXT_INSET - LINE_HEIGHT * (i - 1))
  end
end

return {
  run = function(s)
    _G.Minimap:ClearAllPoints()
    _G.Minimap:SetPoint("CENTER", _G.UIParent, "CENTER")
    s:login()
    s:unit("mouseover", { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80 })
    s:hover("mouseover")
    layoutTooltip()
  end,
}

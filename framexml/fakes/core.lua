-- UIParent, WorldFrame and the standard font objects.
local M = {}

local Flavors = require("tools.flavors")
local Screen = require("ui.screen")

local UI_PARENT_STRATA = "MEDIUM"
local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local FONT_FLAGS = ""
local FONT_SIZES = {
  GameFontNormal = 12,
  GameFontHighlight = 12,
  GameFontNormalSmall = 10,
  GameFontHighlightSmall = 10,
  GameTooltipText = 12,
  GameTooltipHeaderText = 14,
  GameTooltipTextSmall = 10,
}

M.GATE = { gate = "framexml", flavors = Flavors.list }

-- Creates a named kit widget (registering _G[name]) when name passes the FrameXML gate; else returns nil.
function M.createNamed(w, typeName, name, parent)
  if w:passesGate(name, M.GATE) then
    return w.ui.create(typeName, name, parent)
  end
  return nil
end

function M.install(w)
  Screen.install(w)
  local uiParent = M.createNamed(w, "Frame", "UIParent", nil)
  if uiParent then
    uiParent:SetScale(Screen.uiScale(w))
    uiParent:SetSize(Screen.uiSize(w))
    uiParent:SetPoint("BOTTOMLEFT")
    uiParent:SetFrameStrata(UI_PARENT_STRATA)
  end
  local worldFrame = M.createNamed(w, "Frame", "WorldFrame", nil)
  if worldFrame then
    worldFrame:SetSize(w.screen.width, w.screen.height)
    worldFrame:SetPoint("BOTTOMLEFT")
  end
  for name, size in pairs(FONT_SIZES) do
    local font = M.createNamed(w, "Font", name, nil)
    if font then
      font:SetFont(FONT_PATH, size, FONT_FLAGS)
    end
  end
end

return M

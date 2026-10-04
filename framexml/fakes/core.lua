-- UIParent, WorldFrame and the standard font objects.
local M = {}

local Flavors = require("tools.flavors")

local SCREEN_WIDTH = 1920
local SCREEN_HEIGHT = 1080
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

local function screenFrame(w, name)
  local frame = M.createNamed(w, "Frame", name, nil)
  if frame then
    frame:SetSize(SCREEN_WIDTH, SCREEN_HEIGHT)
  end
  return frame
end

function M.install(w)
  local uiParent = screenFrame(w, "UIParent")
  if uiParent then
    uiParent:SetFrameStrata(UI_PARENT_STRATA)
  end
  screenFrame(w, "WorldFrame")
  for name, size in pairs(FONT_SIZES) do
    local font = M.createNamed(w, "Font", name, nil)
    if font then
      font:SetFont(FONT_PATH, size, FONT_FLAGS)
    end
  end
end

return M

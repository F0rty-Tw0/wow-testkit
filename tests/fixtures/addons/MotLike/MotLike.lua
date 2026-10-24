-- MotLike: a kit-authored copy of MouseOverTooltip's minimap-button geometry (UI/MinimapButton.lua, checked against
-- the real file on 2026-10-24): a 31x31 Button under Minimap, strata MEDIUM, level 8, with a 20x20 BACKGROUND, an
-- 18x18 ARTWORK and a 53x53 OVERLAY texture (TOPLEFT to TOPLEFT), placed at angle 0 on a ring of radius
-- Minimap:GetWidth() / 2 + 5. The textures are named so a test can find them in a render snapshot.
local SIZE = 31
local RING_OFFSET = 5
local ANGLE = 0
local ICON = "Interface\\AddOns\\MotLike\\Media\\Icon"
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"

local function addTexture(frame, name, layer, path, size, point)
  local texture = frame:CreateTexture(name, layer)
  texture:SetTexture(path)
  texture:SetSize(size, size)
  texture:SetPoint(point or "CENTER", frame, point or "CENTER")
  return texture
end

local function place(frame, angle)
  local radius = Minimap:GetWidth() / 2 + RING_OFFSET
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", Minimap, "CENTER", math.cos(math.rad(angle)) * radius, math.sin(math.rad(angle)) * radius)
end

local button = CreateFrame("Button", "MotLikeMinimapButton", Minimap)
button:SetSize(SIZE, SIZE)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
addTexture(button, "MotLikeBg", "BACKGROUND", BACKGROUND, 20)
addTexture(button, "MotLikeArt", "ARTWORK", ICON, 18)
addTexture(button, "MotLikeBorder", "OVERLAY", BORDER, 53, "TOPLEFT")
place(button, ANGLE)

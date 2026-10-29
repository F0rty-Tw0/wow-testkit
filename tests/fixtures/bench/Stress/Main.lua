-- Bench fixture (tests/bench): a 40 x 50 grid of cells, each a frame with one texture and one font string (6000
-- regions), and a chain of 300 frames, each anchored under the one before it. Fixed sizes, no randomness.
local FONT = "Fonts\\FRIZQT__.TTF"
local COLUMNS, ROWS = 40, 50
local CELL_WIDTH, CELL_HEIGHT = 40, 20
local CHAIN_LENGTH, CHAIN_HEIGHT = 300, 3

local root = CreateFrame("Frame", "StressRoot", UIParent)
root:SetSize(COLUMNS * CELL_WIDTH, ROWS * CELL_HEIGHT)
root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)

local function cell(column, row)
  local frame = CreateFrame("Frame", nil, root)
  frame:SetSize(CELL_WIDTH, CELL_HEIGHT)
  frame:SetPoint("TOPLEFT", root, "TOPLEFT", column * CELL_WIDTH, -row * CELL_HEIGHT)
  local shade = (column + row) % 2 == 0 and 0.2 or 0.3
  local texture = frame:CreateTexture(nil, "BACKGROUND")
  texture:SetAllPoints()
  texture:SetColorTexture(shade, shade, shade, 1)
  local label = frame:CreateFontString(nil, "ARTWORK")
  label:SetFont(FONT, 10, "")
  label:SetPoint("CENTER")
  label:SetText(column .. "," .. row)
end

for row = 0, ROWS - 1 do
  for column = 0, COLUMNS - 1 do
    cell(column, row)
  end
end

local previous
for _ = 1, CHAIN_LENGTH do
  local link = CreateFrame("Frame", nil, root)
  link:SetSize(20, CHAIN_HEIGHT)
  if previous then
    link:SetPoint("TOP", previous, "BOTTOM")
  else
    link:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  end
  previous = link
end

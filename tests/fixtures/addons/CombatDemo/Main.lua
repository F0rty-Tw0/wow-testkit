-- CombatDemo: a frame per group member with its name and health, the unit's name on every nameplate, and "combat end"
-- in the chat when the player leaves combat. Written like a real addon against the combat world. Health is text, not a
-- status bar: on retail the values are secret in combat, and an addon may only concatenate them.
local COLUMNS = 5
local FONT = "Fonts\\FRIZQT__.TTF"

local members = {}

local function memberFrame(i)
  local frame = CreateFrame("Frame", "CombatDemoMember" .. i, UIParent)
  frame:SetSize(170, 22)
  local column, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20 + column * 176, -20 - row * 26)
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.1, 0.3, 0.1, 0.8)
  frame.text = frame:CreateFontString(nil, "OVERLAY")
  frame.text:SetFont(FONT, 11, "")
  frame.text:SetPoint("LEFT", 4, 0)
  return frame
end

local function unitOf(i)
  if IsInRaid() then
    return "raid" .. i
  end
  return i == 1 and "player" or "party" .. (i - 1)
end

local function refresh()
  local count = math.max(GetNumGroupMembers(), 1)
  for i = 1, math.max(count, #members) do
    local frame = members[i] or memberFrame(i)
    members[i] = frame
    if i <= count then
      local unit = unitOf(i)
      frame.text:SetText(UnitName(unit) .. " " .. UnitHealth(unit) .. "/" .. UnitHealthMax(unit))
      frame:Show()
    else
      frame:Hide()
    end
  end
end

local function showPlateName(unit, shown)
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then
    return
  end
  if not plate.combatDemoName then
    plate.combatDemoName = plate:CreateFontString(nil, "OVERLAY")
    plate.combatDemoName:SetFont(FONT, 10, "OUTLINE")
    plate.combatDemoName:SetPoint("CENTER")
  end
  plate.combatDemoName:SetText(UnitName(unit))
  plate.combatDemoName:SetShown(shown)
end

local events = CreateFrame("Frame", nil, WorldFrame)
for _, event in ipairs({
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "UNIT_HEALTH",
  "NAME_PLATE_UNIT_ADDED",
  "NAME_PLATE_UNIT_REMOVED",
  "PLAYER_REGEN_ENABLED",
}) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    showPlateName(unit, event == "NAME_PLATE_UNIT_ADDED")
  elseif event == "PLAYER_REGEN_ENABLED" then
    print("combat end")
  else
    refresh()
  end
end)

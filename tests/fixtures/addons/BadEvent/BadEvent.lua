-- BadEvent: registers an event no flavor has (line 3), so the error must point at this file.
local frame = CreateFrame("Frame")
frame:RegisterEvent("NOT_AN_EVENT")

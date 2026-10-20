-- Fixed: registers an event every flavor has.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
ns.frame = frame

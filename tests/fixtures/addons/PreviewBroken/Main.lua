-- PreviewBroken: builds a frame, then errors at load (tk preview must still write the snapshot).
local frame = CreateFrame("Frame", "PBFrame", UIParent)
frame:SetSize(100, 50)
frame:SetPoint("CENTER")
error("boom")

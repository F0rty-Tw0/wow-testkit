local text = _G.SessionDemoText

-- A solid background and a label, so the viewer draws the frame.
local function decorate(frame, label, r, g, b)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(r, g, b, 1)
  local caption = frame:CreateFontString(frame:GetName() .. "Label")
  caption:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  caption:SetPoint("CENTER")
  caption:SetText(label)
end

local keys = CreateFrame("Frame", "SessionDemoKeys", UIParent)
keys:SetSize(100, 60)
keys:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
keys:EnableKeyboard(true)
keys:SetPropagateKeyboardInput(true)
decorate(keys, "Keys", 0.1, 0.4, 0.2)
keys:SetScript("OnKeyDown", function(_, key)
  text:SetText("key:" .. key)
end)

local drag = CreateFrame("Frame", "SessionDemoDrag", UIParent)
drag:SetSize(100, 100)
drag:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
drag:SetMovable(true)
drag:EnableMouse(true)
drag:RegisterForDrag("LeftButton")
decorate(drag, "Drag", 0.2, 0.3, 0.6)
drag:SetScript("OnDragStart", drag.StartMoving)
drag:SetScript("OnDragStop", drag.StopMovingOrSizing)

local wheel = CreateFrame("Frame", "SessionDemoWheel", UIParent)
wheel:SetSize(100, 100)
wheel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
wheel:EnableMouseWheel(true)
decorate(wheel, "Wheel", 0.5, 0.35, 0.1)
local count = 0
wheel:SetScript("OnMouseWheel", function(_, delta)
  count = count + delta
  text:SetText("wheel:" .. count)
end)

function SessionDemoToggle(keystate)
  text:SetText("binding:" .. keystate)
end

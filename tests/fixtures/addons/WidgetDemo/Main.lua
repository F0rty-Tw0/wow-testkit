-- Phase-6 demo: one of each widget kind, drawn with colour textures only, written like a real addon.
local FONT = "Fonts\\FRIZQT__.TTF"

local function colored(frame, layer, r, g, b, a)
  local texture = frame:CreateTexture(nil, layer)
  texture:SetColorTexture(r, g, b, a or 1)

  return texture
end

local function backdrop(frame, r, g, b)
  colored(frame, "BACKGROUND", r, g, b):SetAllPoints()
end

local function label(frame, name, text, point, x, y)
  local line = frame:CreateFontString(name, "ARTWORK")
  line:SetFont(FONT, 12, "")
  line:SetPoint(point, frame, point, x, y)
  line:SetText(text)

  return line
end

local root = CreateFrame("Frame", "WidgetDemoRoot", UIParent)
root:SetSize(600, 400)
root:SetPoint("CENTER")
backdrop(root, 0.1, 0.1, 0.12)

-- Button: normal, pushed and highlight art, a click counter and an animated square.
local box = CreateFrame("Frame", "WidgetDemoBox", root)
box:SetSize(40, 40)
box:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -70)
backdrop(box, 1, 0.5, 0)
local group = box:CreateAnimationGroup()
group:SetToFinalAlpha(false)
local fade = group:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0)
fade:SetDuration(1)
local slide = group:CreateAnimation("Translation")
slide:SetOffset(100, 0)
slide:SetDuration(1)

local button = CreateFrame("Button", "WidgetDemoButton", root)
button:SetSize(120, 30)
button:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -20)
button:SetNormalTexture(colored(button, "BACKGROUND", 0.2, 0.4, 0.9))
button:SetPushedTexture(colored(button, "BACKGROUND", 0.1, 0.2, 0.5))
button:SetHighlightTexture(colored(button, "HIGHLIGHT", 1, 1, 1, 0.3))
button:SetNormalFontObject("GameFontHighlight")
button:SetText("Press")
local count = label(root, "WidgetDemoCount", "clicks: 0", "TOPLEFT", 150, -28)
local clicks = 0
button:SetScript("OnClick", function()
  clicks = clicks + 1
  count:SetText("clicks: " .. clicks)
  group:Play()
end)

-- CheckButton with a green check.
local check = CreateFrame("CheckButton", "WidgetDemoCheck", root)
check:SetSize(24, 24)
check:SetPoint("TOPLEFT", root, "TOPLEFT", 260, -20)
backdrop(check, 0.25, 0.25, 0.25)
check:SetCheckedTexture(colored(check, "ARTWORK", 0, 0.8, 0))

-- EditBox.
local edit = CreateFrame("EditBox", "WidgetDemoEdit", root)
edit:SetSize(160, 24)
edit:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -130)
backdrop(edit, 0.2, 0.2, 0.25)
edit:SetFontObject("GameFontHighlight")
edit:SetAutoFocus(false)

-- Slider, horizontal 0..100 in steps of 5, with a red 10x20 thumb.
local slider = CreateFrame("Slider", "WidgetDemoSlider", root)
slider:SetSize(200, 20)
slider:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -180)
backdrop(slider, 0.25, 0.25, 0.25)
slider:SetOrientation("HORIZONTAL")
slider:SetMinMaxValues(0, 100)
slider:SetValueStep(5)
local thumb = colored(slider, "OVERLAY", 1, 0, 0)
thumb:SetSize(10, 20)
slider:SetThumbTexture(thumb)
slider:SetValue(0)

-- StatusBar, green at 40.
local bar = CreateFrame("StatusBar", "WidgetDemoBar", root)
bar:SetSize(200, 20)
bar:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -220)
backdrop(bar, 0.25, 0.25, 0.25)
bar:SetMinMaxValues(0, 100)
bar:SetStatusBarTexture(colored(bar, "ARTWORK", 1, 1, 1))
bar:SetStatusBarColor(0, 1, 0)
bar:SetValue(40)

-- ScrollFrame over a taller child with ten numbered lines.
local scroll = CreateFrame("ScrollFrame", "WidgetDemoScroll", root)
scroll:SetSize(160, 60)
scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 260, -70)
backdrop(scroll, 0.2, 0.2, 0.25)
local content = CreateFrame("Frame", "WidgetDemoContent", scroll)
content:SetSize(160, 200)
scroll:SetScrollChild(content)
for line = 1, 10 do
  label(content, nil, "Line " .. line, "TOPLEFT", 4, -(line - 1) * 20 - 2)
end

-- ScrollingMessageFrame.
local msgs = CreateFrame("ScrollingMessageFrame", "WidgetDemoMsgs", root)
msgs:SetSize(200, 100)
msgs:SetPoint("TOPLEFT", root, "TOPLEFT", 260, -160)
backdrop(msgs, 0.15, 0.15, 0.15)
msgs:SetFading(false)

-- A horizontal gradient strip.
local strip = root:CreateTexture(nil, "ARTWORK")
strip:SetSize(300, 16)
strip:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -270)
strip:SetColorTexture(1, 1, 1, 1)
strip:SetGradient("HORIZONTAL", CreateColor(0, 0, 1, 1), CreateColor(1, 0, 0, 1))

StaticPopupDialogs["WIDGETDEMO_CONFIRM"] = {
  text = "Really accept?",
  button1 = "Accept",
  button2 = "Cancel",
  OnAccept = function()
    print("accepted")
  end,
}

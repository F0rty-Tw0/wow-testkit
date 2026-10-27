-- FauxScrollFrame_Update, GetOffset, SetOffset and OnVerticalScroll, ScrollFrameTemplate_OnMouseWheel. Kit-authored bodies
-- over row W71. A named frame's children are looked up by the global names the client builds ("<name>ScrollBar") first and
-- then by key, because the kit's templates give their children keys only.
local M = {}

-- Localized: addon code may assign globals named ipairs or rawget.
local ipairs, rawget = ipairs, rawget
local floor = math.floor

-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local HALF = 2
local ROUNDING = 0.5

local function child(frame, key, ...)
  local name = frame:GetName()
  local found = name and rawget(_G, name .. key)
  if found then
    return found
  end
  local object = frame
  for _, part in ipairs({ key, ... }) do
    object = object and object[part]
  end

  return object
end

-- source: row W71 (confirmed) FauxScrollFrame_GetChildFrames, blizzard_sharedxml/securescrolltemplates.lua:149: the scroll bar,
-- scroll child and arrow buttons.
local function childFrames(frame)
  local bar = child(frame, "ScrollBar")

  return bar,
    child(frame, "ScrollChildFrame"),
    bar.ScrollUpButton or child(frame, "ScrollBarScrollUpButton"),
    bar.ScrollDownButton or child(frame, "ScrollBarScrollDownButton")
end

local function setEnabled(button, enabled)
  if enabled then
    button:Enable()
  else
    button:Disable()
  end
end

-- Every row button named <button>1 .. <button><count>, set to width.
local function widenRows(button, count, width)
  for index = 1, count do
    rawget(_G, button .. index):SetWidth(width)
  end
end

local function sizeRange(bar, childFrame, numItems, numToDisplay, buttonHeight)
  local range = numItems > 0 and (numItems - numToDisplay) * buttonHeight or 0
  range = range < 0 and 0 or range
  if numItems > 0 then
    childFrame:Show()
  else
    childFrame:Hide()
  end
  bar:SetMinMaxValues(0, range)
  bar:SetValueStep(buttonHeight)
  bar:SetStepsPerPage(numToDisplay - 1)
  childFrame:SetHeight(numItems * buttonHeight)

  return range
end

-- source: row W71 (confirmed) blizzard_sharedxml/securescrolltemplates.lua:158 answers 1 when the bar shows, else nil;
-- it shows when there are more items than rows (or alwaysShowScrollBar), and a hidden frame resets the bar to the top.
local function update(
  frame,
  numItems,
  numToDisplay,
  buttonHeight,
  button,
  smallWidth,
  bigWidth,
  highlightFrame,
  smallHighlightWidth,
  bigHighlightWidth,
  alwaysShow
)
  local bar, childFrame, upButton, downButton = childFrames(frame)
  local shows = numItems > numToDisplay or alwaysShow
  if shows then
    frame:Show()
  else
    bar:SetValue(0)
    frame:Hide()
  end
  if shows then
    local range = sizeRange(bar, childFrame, numItems, numToDisplay, buttonHeight)
    setEnabled(upButton, bar:GetValue() ~= 0)
    setEnabled(downButton, bar:GetValue() ~= range)
  end
  if highlightFrame then
    highlightFrame:SetWidth(shows and smallHighlightWidth or bigHighlightWidth)
  end
  if button then
    widenRows(button, numToDisplay, shows and smallWidth or bigWidth)
  end

  return shows and 1 or nil
end

-- source: row W71 (confirmed) :227 sets the bar to value, the offset to floor(value / itemHeight + 0.5), then calls
-- updateFunction(frame).
local function onVerticalScroll(frame, value, itemHeight, updateFunction)
  local bar = childFrames(frame)
  bar:SetValue(value)
  frame.offset = floor(value / itemHeight + ROUNDING)
  if updateFunction then
    updateFunction(frame)
  end
end

local function getOffset(frame)
  return frame.offset or 0
end

local function setOffset(frame, offset)
  frame.offset = offset
end

-- source: row W71 (confirmed) blizzard_sharedxml/securescrolltemplates.lua:54 steps by scrollBar.scrollStep or half the
-- bar's height; a positive wheel value scrolls up.
local function onMouseWheel(frame, value, scrollBar)
  local bar = scrollBar or childFrames(frame)
  local step = bar.scrollStep or bar:GetHeight() / HALF
  bar:SetValue(bar:GetValue() + (value > 0 and -step or step))
end

function M.install(w)
  w:install("FauxScrollFrame_Update", update, KETHO_GATE)
  w:install("FauxScrollFrame_OnVerticalScroll", onVerticalScroll, KETHO_GATE)
  w:install("FauxScrollFrame_GetOffset", getOffset, KETHO_GATE)
  w:install("FauxScrollFrame_SetOffset", setOffset, KETHO_GATE)
  w:install("ScrollFrameTemplate_OnMouseWheel", onMouseWheel, KETHO_GATE)
end

return M

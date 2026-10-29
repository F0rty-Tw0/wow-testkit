-- Hand-written Button and CheckButton behaviour. A button's state is st.btn = { state, locked, offset, tex = { normal,
-- pushed, highlight, disabled, checked, disabledChecked }, fs, fonts = { normal, highlight, disabled } }, each key
-- present only once set (ui/button_state.lua reads it; the state textures live in ui/behaviour_button_textures.lua).
-- The button text is the FontString st.btn.fs, which ui/layout_shift.lua moves while the button is PUSHED. The
-- methods register through Typed.add for "button", so M.methods stays empty. Methods are fn(w, obj, st, ...) like
-- ui/behaviour.lua.
local M = {}

local AddonEnv = require("addon_env")
local BehaviourText = require("ui.behaviour_text")
local FontChain = require("ui.font_chain")
local State = require("ui.button_state")
local Shift = require("ui.layout_shift")
local Slot = require("ui.role_slot")
local Typed = require("ui.typed")

require("ui.behaviour_button_textures")

M.methods = {}

local DEFAULT_STATE = "NORMAL"

-- State and queries ---------------------------------------------------------------------------------------

-- source: row V9, wiki Layer, Details: "Setting Frame:EnableMouse() causes HIGHLIGHT to show/hide as the cursor hovers
-- the Frame." True while the mouse focus is frame or a descendant of it.
function M.mouseWithin(w, frame)
  local cursor = w.input and w.input.mouseFocus
  while cursor do
    if cursor == frame then
      return true
    end
    local st = w.ui.state[cursor]
    cursor = st and st.parent
  end

  return false
end

-- source: assumed (W17) the highlight draws while the mouse is over an enabled button or after LockHighlight.
function M.highlightShown(w, owner)
  local st = w.ui.state[owner]

  return State.read(st).locked == true or (not State.isDisabled(st) and M.mouseWithin(w, owner))
end

-- source: assumed (W17, W24) a pushed or disabled button shows that state's texture, the normal one when it has none;
-- the checked texture draws while checked and enabled, the disabled-checked one while checked and disabled.
-- True when the texture region that fills role of owner draws.
function M.shown(w, owner, role)
  local st = w.ui.state[owner]
  if role == "highlight" then
    return M.highlightShown(w, owner)
  elseif role == "checked" then
    return st.checked == true and not State.isDisabled(st)
  elseif role == "disabledChecked" then
    return st.checked == true and State.isDisabled(st)
  end
  local display = State.displayState(st)
  if role == "normal" then
    return display == "normal" or Slot.held(w, State.read(st).tex, display, owner) == nil
  end

  return display == role
end

-- source: assumed (W17) a region that fills several roles of owner (role is its mark) draws while any of them shows.
function M.regionShown(w, owner, region, role)
  if M.shown(w, owner, role) then
    return true
  end
  for other, held in pairs(State.read(w.ui.state[owner]).tex) do
    if held == region and M.shown(w, owner, other) then
      return true
    end
  end

  return false
end

-- source: assumed (W22) the shown text uses the state's font object (disabled; highlight while hovered), else the
-- normal one. The font object the button text shows, or nil.
function M.fontFor(w, owner)
  local st = w.ui.state[owner]
  local fonts = State.read(st).fonts
  if State.displayState(st) == "disabled" then
    return fonts.disabled or fonts.normal
  end
  if M.highlightShown(w, owner) then
    return fonts.highlight or fonts.normal
  end

  return fonts.normal
end

-- source: confirmed (W16) wiki API_Button_SetButtonState: DISABLED, NORMAL or PUSHED, and a `lock` argument (api
-- SimpleButtonAPI.lua:291); nothing in the kit pushes a button on its own, so the lock has nothing to hold.
local function setButtonState(_, _, st, state)
  State.write(st).state = state
end

-- source: assumed (W16) a button no state was set on is NORMAL.
local function getButtonState(_, _, st)
  return State.read(st).state or DEFAULT_STATE
end

-- source: assumed (W20) the default offset is 1, -1 (ui/layout_shift.lua).
local function setPushedTextOffset(_, _, st, x, y)
  State.write(st).offset = { x, y }
end

local function getPushedTextOffset(_, _, st)
  return Shift.pushedOffset(st.btn)
end

local function setHighlightLocked(_, _, st, locked)
  State.write(st).locked = locked and true or false
end

local function lockHighlight(w, obj, st)
  setHighlightLocked(w, obj, st, true)
end

local function unlockHighlight(w, obj, st)
  setHighlightLocked(w, obj, st, false)
end

local function isHighlightLocked(_, _, st)
  return State.read(st).locked == true
end

-- Button text -------------------------------------------------------------------------------------------------

-- Makes fs the button text; its state remembers the button (textOwner), so the font chain finds the state font object.
local function adoptText(w, obj, st, fs)
  local btn = State.write(st)
  local previous = btn.fs and w.ui.state[btn.fs]
  if previous then
    previous.textOwner = nil
  end
  btn.fs = fs
  local fsState = fs and w.ui.state[fs]
  if fsState then
    fsState.textOwner = obj
  end
end

-- source: assumed (W22) the text of a button shows the font object of the button's state; ui/font_chain.lua asks this
-- before the text's own font object.
FontChain.ownerFont = function(w, st)
  return st.textOwner and M.fontFor(w, st.textOwner)
end

-- The button text FontString, created over the whole button on first use.
local function fontString(w, obj, st)
  local btn = State.write(st)
  if not btn.fs then
    adoptText(w, obj, st, obj:CreateFontString(nil, "ARTWORK"))
    btn.fs:SetAllPoints()
  end

  return btn.fs
end

local function setFontString(w, obj, st, fs)
  adoptText(w, obj, st, fs)
end

local function getFontString(_, _, st)
  return State.read(st).fs
end

local function setText(w, obj, st, text)
  local fs = fontString(w, obj, st)
  BehaviourText.methods.SetText(w, fs, w.ui.state[fs], text)
end

local function setFormattedText(w, obj, st, format, ...)
  local fs = fontString(w, obj, st)
  BehaviourText.methods.SetFormattedText(w, fs, w.ui.state[fs], format, ...)
end

-- source: confirmed (W21) GetText is not nilable, so a button without text reads "".
local function getText(w, _, st)
  local fs = State.read(st).fs
  local text = fs and w.ui.state[fs].text

  return text or ""
end

-- source: assumed (W23) the text width and height are the button text's string width and height.
local function getTextWidth(w, _, st)
  local fs = State.read(st).fs

  return fs and BehaviourText.methods.GetStringWidth(w, fs) or 0
end

local function getTextHeight(w, _, st)
  local fs = State.read(st).fs

  return fs and BehaviourText.methods.GetStringHeight(w, fs) or 0
end

local function setFontObject(state)
  return function(w, _, st, font)
    local fonts = State.write(st).fonts
    if type(font) == "string" then
      font = AddonEnv.global(w, font)
    end
    fonts[state] = font
  end
end

local function getFontObject(state)
  return function(_, _, st)
    return State.read(st).fonts[state]
  end
end

-- Registration --------------------------------------------------------------------------------------------------

local BUTTON_METHODS = {
  SetButtonState = setButtonState,
  GetButtonState = getButtonState,
  SetPushedTextOffset = setPushedTextOffset,
  GetPushedTextOffset = getPushedTextOffset,
  LockHighlight = lockHighlight,
  UnlockHighlight = unlockHighlight,
  SetHighlightLocked = setHighlightLocked,
  IsHighlightLocked = isHighlightLocked,
  SetFontString = setFontString,
  GetFontString = getFontString,
  SetText = setText,
  SetFormattedText = setFormattedText,
  GetText = getText,
  GetTextWidth = getTextWidth,
  GetTextHeight = getTextHeight,
}
for name, impl in pairs(BUTTON_METHODS) do
  Typed.add(name, "button", impl)
end

for _, state in ipairs({ "Normal", "Highlight", "Disabled" }) do
  Typed.add("Set" .. state .. "FontObject", "button", setFontObject(state:lower()))
  Typed.add("Get" .. state .. "FontObject", "button", getFontObject(state:lower()))
end

return M

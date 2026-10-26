-- EditBox behaviour: the cursor and selection, typing limits (max letters, numeric), the password mask, multi-line,
-- auto focus, history lines and text insets. State lives in st.edit (a box nothing was set on has none and reads
-- M.DEFAULT). Positions count UTF-8 characters, 0 before the first. Methods register through Typed.add for "editbox", so
-- M.methods stays empty; input.lua types through M.typeChar and input_keys.lua deletes through M.backspace.
local M = {}

local BehaviourInput = require("ui.behaviour_input")
local Typed = require("ui.typed")

local unpack = unpack

M.methods = {}

-- One UTF-8 character: a lead byte (%z is NUL in Lua 5.1 patterns) plus its continuation bytes.
M.UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local DIGIT = "^%d$"
local NUMBER_PREFIX = "^%d+"
local MASK = "*"

local function newEdit()
  return {
    cursor = 0,
    maxLetters = 0,
    numeric = false,
    password = false,
    multiLine = false,
    autoFocus = true,
    history = {},
    insets = { 0, 0, 0, 0 },
  }
end

M.DEFAULT = newEdit()

-- The edit state of st, made on first use.
local function of(st)
  st.edit = st.edit or newEdit()

  return st.edit
end

-- The edit state of st for reading: M.DEFAULT for a box nothing was set on. Treat the result as read-only.
function M.read(st)
  return st.edit or M.DEFAULT
end

local function split(text)
  local list = {}
  for char in text:gmatch(M.UTF8_CHAR) do
    list[#list + 1] = char
  end

  return list
end

local function clamp(value, last)
  return math.max(0, math.min(value, last))
end

-- The characters from..to (inclusive, 1-based) joined; "" when the range is empty.
local function slice(list, from, to)
  return table.concat(list, "", from, to)
end

local function charCount(text)
  return #split(text)
end

-- The text a box shows: the mask for a password box, else its text.
function M.displayText(st)
  local text = st.text or ""

  return M.read(st).password and MASK:rep(charCount(text)) or text
end

-- The range [from, to) an edit replaces: the selection, else the empty range at the cursor.
local function editRange(edit, last)
  local selection = edit.selection
  if selection then
    return clamp(selection.from, last), clamp(selection.to, last)
  end
  local cursor = clamp(edit.cursor, last)

  return cursor, cursor
end

-- Puts insert over the characters from..to, moves the cursor after it and drops the selection.
local function replace(st, edit, list, from, to, insert)
  st.text = slice(list, 1, from) .. insert .. slice(list, to + 1, #list)
  edit.cursor = from + charCount(insert)
  edit.selection = nil
end

-- source: assumed (W35) typed input stops at max letters, counted in characters; a selection being replaced makes room.
-- source: confirmed (W36) wiki API_EditBox_SetNumeric: "Decimal places [.] and other symbols are also stripped."
-- Inserts ch at the cursor over the selection; false when the box refuses it.
function M.typeChar(st, ch)
  local edit = of(st)
  if edit.numeric and not ch:find(DIGIT) then
    return false
  end
  local list = split(st.text or "")
  local from, to = editRange(edit, #list)
  local limit = edit.maxLetters
  if limit > 0 and #list - (to - from) >= limit then
    return false
  end
  replace(st, edit, list, from, to, ch)

  return true
end

-- source: assumed (K1, W32) BACKSPACE removes the selection, else the character before the cursor. False when nothing
-- was removed.
function M.backspace(st)
  local edit = of(st)
  local list = split(st.text or "")
  local from, to = editRange(edit, #list)
  if from == to then
    from = from - 1
  end
  if from < 0 then
    return false
  end
  replace(st, edit, list, from, to, "")

  return true
end

-- source: confirmed (W33) wiki API_EditBox_Insert: "Inserts text at the current cursor position."; assumed (W33) the
-- cursor moves after the insert and no script fires.
local function insert(_, _, st, text)
  for char in tostring(text):gmatch(M.UTF8_CHAR) do
    M.typeChar(st, char)
  end
end

-- source: assumed (W32) a fresh cursor is 0, SetCursorPosition clamps to 0..#text and drops the selection, SetText
-- puts the cursor at the end (before its scripts run).
local function getCursorPosition(_, _, st)
  return M.read(st).cursor
end

local function setCursorPosition(_, _, st, position)
  local edit = of(st)
  edit.cursor = clamp(position, charCount(st.text or ""))
  edit.selection = nil
end

local function setText(w, obj, st, text)
  local edit = of(st)
  edit.cursor = charCount(tostring(text or ""))
  edit.selection = nil
  BehaviourInput.setEditText(w, obj, st, text)
end

-- source: confirmed (W34) wiki API_EditBox_HighlightText: "Leaving out both parameters, as in EditBox:HighlightText(),
-- will highlight the entire EditBox content."; start "defaults to 0"; stop "defaults to the end of the string"; "-1 is
-- the end of the string". An empty range selects nothing.
local function highlightText(_, _, st, start, stop)
  local edit = of(st)
  local last = charCount(st.text or "")
  local from = clamp(start or 0, last)
  local to = (stop == nil or stop < 0) and last or clamp(stop, last)
  edit.selection = from < to and { from = from, to = to } or nil
end

-- source: confirmed (W36) wiki API_EditBox_GetNumber: "It will return number recognized so far, or 0 if there were no
-- valid digits recognized."; "The function will never return nil."
local function getNumber(_, _, st)
  return tonumber((st.text or ""):match(NUMBER_PREFIX)) or 0
end

local function setNumber(w, obj, st, number)
  setText(w, obj, st, tostring(number))
end

local function getDisplayText(_, _, st)
  return M.displayText(st)
end

local function addHistoryLine(_, _, st, line)
  local history = of(st).history
  history[#history + 1] = line
end

-- source: assumed (W40, plan Task 6.5) the count of stored lines; the api's numHistoryLines may be the box's maximum.
local function getHistoryLines(_, _, st)
  return #M.read(st).history
end

local function setTextInsets(_, _, st, left, right, top, bottom)
  of(st).insets = { left, right, top, bottom }
end

local function getTextInsets(_, _, st)
  return unpack(M.read(st).insets)
end

-- A getter/setter pair over one flag or number of st.edit.
local function property(key, getter, setter, toValue)
  Typed.add(getter, "editbox", function(_, _, st)
    return M.read(st)[key]
  end)
  Typed.add(setter, "editbox", function(_, _, st, value)
    of(st)[key] = toValue(value)
  end)
end

local function toBoolean(value)
  return value and true or false
end

local function toNumber(value)
  return value or 0
end

property("maxLetters", "GetMaxLetters", "SetMaxLetters", toNumber)
property("numeric", "IsNumeric", "SetNumeric", toBoolean)
property("password", "IsPassword", "SetPassword", toBoolean)
property("multiLine", "IsMultiLine", "SetMultiLine", toBoolean)
property("autoFocus", "IsAutoFocus", "SetAutoFocus", toBoolean)

local EDIT_BOX_METHODS = {
  GetCursorPosition = getCursorPosition,
  SetCursorPosition = setCursorPosition,
  SetText = setText,
  Insert = insert,
  HighlightText = highlightText,
  GetNumber = getNumber,
  SetNumber = setNumber,
  GetDisplayText = getDisplayText,
  AddHistoryLine = addHistoryLine,
  GetHistoryLines = getHistoryLines,
  SetTextInsets = setTextInsets,
  GetTextInsets = getTextInsets,
}
for name, impl in pairs(EDIT_BOX_METHODS) do
  Typed.add(name, "editbox", impl)
end

return M

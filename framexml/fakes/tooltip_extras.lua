-- GameTooltip methods beyond tooltip.lua's: AppendText, padding, IsOwned, FadeOut and the hyperlink, item and spell
-- setters. Each is fn(w, self, tip, ...) like tooltip.lua's methods, which merges this table; per-tooltip state lives in
-- tip (st.tooltip).
local M = {}

local TooltipLines = require("framexml.fakes.tooltip_lines")

local methods = {}
M.methods = methods

local unpack = unpack

local PADDING_FIELDS = 4
local NO_PADDING = { 0, 0, 0, 0 }
local FULL_LINK_PATTERN = "|H(%a+):(%-?%d+)"
local BARE_LINK_PATTERN = "^(%a+):(%-?%d+)"

-- The id as text when data names no one: `<kind>:<id>`.
local function fallbackText(kind, id)
  return kind .. ":" .. tostring(id)
end

-- The name GetItemInfo or GetSpellInfo answers for id (a string, or a table with a name field), else nil.
local function dataName(w, apiName, id)
  local answer = TooltipLines.ask(w, apiName, id)
  if type(answer) == "table" then
    answer = answer.name
  end

  return type(answer) == "string" and answer or nil
end

local function setSingleLine(w, self, apiName, kind, id)
  self:ClearLines()
  self:AddLine(dataName(w, apiName, id) or fallbackText(kind, id))
end

-- source: row W56 (assumed) a name or id with no data source adds one white line `item:<id>`; with GetItemInfo the item
-- name replaces it.
function methods.SetItemByID(w, self, _, id)
  setSingleLine(w, self, "GetItemInfo", "item", id)
end

-- source: row W56 (assumed) the same for `spell:<id>` with GetSpellInfo.
function methods.SetSpellByID(w, self, _, id)
  setSingleLine(w, self, "GetSpellInfo", "spell", id)
end

-- source: row W56 (assumed) "item:<id>" equals SetItemByID and "spell:<id>" equals SetSpellByID, also inside a full
-- hyperlink (|Hitem:<id>:...|h); a link of another type shows its `<type>:<id>` as one line.
function methods.SetHyperlink(w, self, tip, link)
  local text = tostring(link)
  local kind, id = text:match(FULL_LINK_PATTERN)
  if not kind then
    kind, id = text:match(BARE_LINK_PATTERN)
  end
  if kind == "item" then
    return methods.SetItemByID(w, self, tip, tonumber(id))
  elseif kind == "spell" then
    return methods.SetSpellByID(w, self, tip, tonumber(id))
  end
  self:ClearLines()
  self:AddLine(kind and fallbackText(kind, id) or text)
end

-- source: row W56 (confirmed) AppendText appends to the last line; with no line there is nothing to append to (assumed).
function methods.AppendText(_, _, tip, text)
  local line = tip.Left[tip.count]
  if line then
    line:SetText((line:GetText() or "") .. tostring(text))
  end
end

-- source: row W56 (confirmed the default 0 and the storing; the argument order is the api's: right, bottom, left, top).
-- An omitted value is 0 (assumed).
function methods.SetPadding(_, _, tip, right, bottom, left, top)
  tip.padding = { right or 0, bottom or 0, left or 0, top or 0 }
end

function methods.GetPadding(_, _, tip)
  return unpack(tip.padding or NO_PADDING, 1, PADDING_FIELDS)
end

-- source: row W56 (assumed) true when the owner is the frame.
function methods.IsOwned(_, _, tip, frame)
  return tip.owner == frame
end

-- source: row W56 (assumed, kit choice) the client fades over seconds; the kit hides at once.
function methods.FadeOut(_, self)
  self:Hide()
end

return M

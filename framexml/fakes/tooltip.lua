-- GameTooltip (line font strings, GameTooltipStatusBar, NineSlice), GameTooltip_SetDefaultAnchor,
-- TooltipDataProcessor (retail, forever) and GameTooltip:SetUnit. The tooltip methods are added to the world's
-- GameTooltip widget class whatever the flavor's Ketho WidgetAPI lists (retail's lacks SetUnit and GetUnit), so
-- every GameTooltip widget of the world has them; per-tooltip state lives in its widget state (st.tooltip).
local M = {}

local Core = require("framexml.fakes.core")
local TooltipLines = require("framexml.fakes.tooltip_lines")
local TooltipUnit = require("framexml.fakes.tooltip_unit")

local unpack = unpack

local TOOLTIP_NAME = "GameTooltip"
local DEFAULT_ANCHOR = "ANCHOR_NONE"
local DEFAULT_POINT = "BOTTOMRIGHT"
local DEFAULT_OFFSET_X = -13
local DEFAULT_OFFSET_Y = 64
local DEFAULT_CHANNEL = 1
local COLOR_FIELDS = 4
local GETTER_NAME = "GetUnit"
local ALL_TYPES = "ALL"
local SIDES = { "Left", "Right" }
local PROCESSOR_GATE = { gate = "framexml", flavors = { "retail", "forever" } }
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }
-- The client's values; installed only where the manifest lacks the enum (every flavor's has it today).
local FALLBACK_ENUMS = {
  TooltipDataType = { Item = 0, Unit = 2 },
  TooltipDataLineType = { None = 0, UnitName = 2 },
}

local methods = {}

-- Lines ------------------------------------------------------------------------------------------------------

local function lineString(w, tip, tooltip, side, index)
  local list = tip[side]
  if not list[index] then
    local name = tip.name and (tip.name .. "Text" .. side .. index)
    list[index] = w.ui.create("FontString", name, tooltip)
  end
  return list[index]
end

local function fill(fontString, text, r, g, b)
  fontString:SetText(text ~= nil and tostring(text) or nil)
  fontString:SetTextColor(r or DEFAULT_CHANNEL, g or DEFAULT_CHANNEL, b or DEFAULT_CHANNEL)
  fontString:Show()
end

local function blank(fontString)
  fontString:SetText(nil)
  fontString:Hide()
end

function methods.AddLine(w, self, tip, text, r, g, b)
  tip.count = tip.count + 1
  fill(lineString(w, tip, self, "Left", tip.count), text, r, g, b)
  blank(lineString(w, tip, self, "Right", tip.count))
end

function methods.AddDoubleLine(w, self, tip, left, right, lr, lg, lb, rr, rg, rb)
  tip.count = tip.count + 1
  fill(lineString(w, tip, self, "Left", tip.count), left, lr, lg, lb)
  fill(lineString(w, tip, self, "Right", tip.count), right, rr, rg, rb)
end

-- Empties and hides every line (kept for reuse) and forgets the unit.
function methods.ClearLines(_, _, tip)
  for _, side in ipairs(SIDES) do
    for _, fontString in ipairs(tip[side]) do
      blank(fontString)
    end
  end
  tip.count = 0
  tip.unit = nil
  tip.data = nil
end

function methods.NumLines(_, _, tip)
  return tip.count
end

function methods.SetText(w, self, tip, text, r, g, b)
  methods.ClearLines(w, self, tip)
  methods.AddLine(w, self, tip, text, r, g, b)
end

-- Owner and anchor -------------------------------------------------------------------------------------------

function methods.SetOwner(_, _, tip, owner, anchor)
  tip.owner, tip.anchor = owner, anchor
end

function methods.GetOwner(_, _, tip)
  return tip.owner
end

function methods.SetAnchorType(_, _, tip, anchor)
  tip.anchor = anchor
end

function methods.GetAnchorType(_, _, tip)
  return tip.anchor
end

local function setDefaultAnchor(tooltip, parent)
  tooltip:SetOwner(parent, DEFAULT_ANCHOR)
  tooltip:ClearAllPoints()
  tooltip:SetPoint(DEFAULT_POINT, _G.UIParent, DEFAULT_POINT, DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y)
end

-- Units ------------------------------------------------------------------------------------------------------

function methods.GetUnit(w, _, tip)
  return TooltipUnit.get(w, tip)
end

function methods.GetProcessingTooltipInfo(_, _, tip)
  return tip.processing
end

local function addDataLine(w, self, tip, line)
  local left = line.leftColor
  if line.rightText == nil then
    return methods.AddLine(w, self, tip, line.leftText, left.r, left.g, left.b)
  end
  local right = line.rightColor or {}
  methods.AddDoubleLine(w, self, tip, line.leftText, line.rightText, left.r, left.g, left.b, right.r, right.g, right.b)
end

-- Runs byType[key] then byType[ALL] callbacks with (tooltip, data) under "addon" context, errors going to the
-- world's error path. With stopOnTrue, returns true at the first callback returning a true value.
local function runCallbacks(w, byType, key, tooltip, data, stopOnTrue)
  for _, list in ipairs({ byType[key] or {}, byType[ALL_TYPES] or {} }) do
    for _, fn in ipairs(list) do
      local results = w:run("addon", w.try, w, fn, tooltip, data)
      if stopOnTrue and results[1] and results[2] then
        return true
      end
    end
  end
  return false
end

local function processData(w, self, tip, data)
  local callbacks = w.tooltipCallbacks
  if runCallbacks(w, callbacks.tooltipPre, data.type, self, data, true) then
    return
  end
  for _, line in ipairs(data.lines) do
    if not runCallbacks(w, callbacks.linePre, line.type, self, line, true) then
      addDataLine(w, self, tip, line)
      runCallbacks(w, callbacks.linePost, line.type, self, line, false)
    end
  end
  runCallbacks(w, callbacks.tooltipPost, data.type, self, data, false)
end

-- Retail/forever: TooltipDataProcessor callbacks around each line; Classic: lines, then OnTooltipSetUnit. A unit
-- that does not exist leaves the tooltip empty and GetUnit answering nothing.
function methods.SetUnit(w, self, tip, unit)
  methods.ClearLines(w, self, tip)
  if not TooltipLines.ask(w, "UnitExists", unit) then
    return
  end
  tip.unit = unit
  local data = TooltipLines.build(w, unit)
  if not w.tooltipCallbacks then
    for _, line in ipairs(data.lines) do
      addDataLine(w, self, tip, line)
    end
    return w:callScript(self, "OnTooltipSetUnit")
  end
  tip.data = data
  tip.processing = { tooltipData = data, getterName = GETTER_NAME, getterArgs = { unit } }
  processData(w, self, tip, data)
  tip.processing = nil
end

-- Install ----------------------------------------------------------------------------------------------------

local function tipOf(w, self, label)
  local st = w.ui.state[self]
  if not st then
    error(label .. ": self is not a widget of this world", 3)
  end
  st.tooltip = st.tooltip or { name = st.name, Left = {}, Right = {}, count = 0 }
  return st.tooltip
end

-- Adds the tooltip methods to the world's GameTooltip class (the metatable __index every such widget shares).
local function attachMethods(w, tooltip)
  local index = getmetatable(tooltip).__index
  for name, impl in pairs(methods) do
    local label = TOOLTIP_NAME .. ":" .. name
    index[name] = function(self, ...)
      return impl(w, self, tipOf(w, self, label), ...)
    end
  end
end

local function addColorAccessors(slice, field)
  local values = { DEFAULT_CHANNEL, DEFAULT_CHANNEL, DEFAULT_CHANNEL, DEFAULT_CHANNEL }
  slice["Set" .. field] = function(_, r, g, b, a)
    values = { r, g, b, a or DEFAULT_CHANNEL }
  end
  slice["Get" .. field] = function()
    return unpack(values, 1, COLOR_FIELDS)
  end
end

-- tooltip.NineSlice: a child frame carrying NineSlicePanelMixin's border and center color accessors.
local function nineSlice(w, tooltip)
  local slice = w.ui.create("Frame", nil, tooltip)
  addColorAccessors(slice, "BorderColor")
  addColorAccessors(slice, "CenterColor")
  return slice
end

local function installEnumFallbacks(w)
  for name, values in pairs(FALLBACK_ENUMS) do
    if _G.Enum[name] == nil then
      local copy = {}
      for key, value in pairs(values) do
        copy[key] = value
      end
      w:set("Enum." .. name, copy)
    end
  end
end

local function processor(callbacks)
  local function adder(byType)
    return function(dataType, fn)
      if dataType == nil or type(fn) ~= "function" then
        error("TooltipDataProcessor: expected (type, function)", 2)
      end
      byType[dataType] = byType[dataType] or {}
      table.insert(byType[dataType], fn)
    end
  end
  return {
    AllTypes = ALL_TYPES,
    AddTooltipPreCall = adder(callbacks.tooltipPre),
    AddTooltipPostCall = adder(callbacks.tooltipPost),
    AddLinePreCall = adder(callbacks.linePre),
    AddLinePostCall = adder(callbacks.linePost),
  }
end

-- GameTooltip is created eagerly (hidden, like the client's) so it wins over the lazy frame-name lookup.
function M.install(w)
  installEnumFallbacks(w)
  local tooltip = Core.createNamed(w, "GameTooltip", TOOLTIP_NAME, _G.UIParent)
  attachMethods(w, tooltip)
  tooltip:Hide()
  Core.createNamed(w, "StatusBar", "GameTooltipStatusBar", tooltip)
  tooltip.NineSlice = nineSlice(w, tooltip)
  w:install("GameTooltip_SetDefaultAnchor", setDefaultAnchor, KETHO_GATE)
  local callbacks = { tooltipPre = {}, tooltipPost = {}, linePre = {}, linePost = {} }
  if w:install("TooltipDataProcessor", processor(callbacks), PROCESSOR_GATE) then
    w.tooltipCallbacks = callbacks
  end
  TooltipUnit.install(w, tooltip, tipOf)
end

return M

-- XML attributes of frames and regions as setters: frame and region are tables of fn(w, obj, st, value, node, session)
-- keyed by the lowercased attribute name (the parser lowercases them). A setter that returns false could not apply the
-- attribute to this widget; a name with no setter is unsupported. Both are reported by apply. Identity attributes (name,
-- parentKey, parentArray) belong to ui/xml_build.lua.
local M = {}

local AddonEnv = require("addon_env")
local BehaviourRegions = require("ui.behaviour_regions")
local TemplateApply = require("ui.template_apply")

-- Identity attributes: built by ui/xml_build.lua (XmlBuild.attach), so no setter here.
M.IDENTITY = { name = true, parentkey = true, parentarray = true }
-- Applied before every other attribute, in this order; the rest follow by name.
local EARLY = { inherits = 1, mixin = 2, securemixin = 3 }

local function callIfPresent(obj, method, ...)
  if obj[method] then
    obj[method](obj, ...)
    return true
  end
  return false
end

local function boolSetter(method)
  return function(_, obj, _, value)
    return callIfPresent(obj, method, value == "true")
  end
end

local function numberSetter(method)
  return function(_, obj, _, value)
    local n = tonumber(value)
    return n == nil or callIfPresent(obj, method, n)
  end
end

local function stringSetter(method)
  return function(_, obj, _, value)
    return callIfPresent(obj, method, value)
  end
end

local function skip() end

-- source: confirmed (row X27) Blizzard_SharedXML/UI.xsd:18-30 FRAMESTRATA, the type of frameStrata (:836); assumed:
-- another value, in any case, is reported and ignored, so the frame keeps its strata. PARENT (tbc 70577 UI.xsd:18-31, the
-- default) means inherit, so it sets nothing; assumed the same on retail, whose UI.xsd leaves it out.
local FRAMESTRATA = {}
for _, strata in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP", "BLIZZARD" }) do
  FRAMESTRATA[strata] = true
end

local function frameStrata(_, frame, st, value, node, session)
  if value:upper() == "PARENT" then
    st.strata = nil -- nil strata inherits the parent's (behaviour_render.lua), also over a template's
    return
  end
  if FRAMESTRATA[value:upper()] then
    return callIfPresent(frame, "SetFrameStrata", value)
  end
  session.reportAt(node.line, "frameStrata '" .. value .. "' is not a FRAMESTRATA; ignored")
end

-- source: wiki XML/LayoutFrame, hidden "Controls the frame's initial visibility" (row X7). Writes the state, not Hide,
-- so no OnHide runs (assumed). `false` shows again what a template hid.
local function hidden(_, _, st, value)
  st.shown = value ~= "true"
end

local function setAllPoints(_, obj, _, value)
  return value ~= "true" or callIfPresent(obj, "SetAllPoints")
end

-- source: wiki XML/LayoutFrame, `mixin` / `secureMixin` "Inherits a comma-separated list of Lua mixins". secureMixin is
-- copied the same way (its secure wrapping is not modelled); a name is recorded as templates record theirs, found or not.
local function mixin(w, frame, st, value, _, session)
  for name in value:gmatch("[^,%s]+") do
    TemplateApply.recordMixin(st, name)
    local source = AddonEnv.global(w, name, true)
    if type(source) == "table" then
      TemplateApply.copyMixin(frame, source)
    else
      session.report("mixin:" .. name, "mixin '" .. name .. "' not found")
    end
  end
end

M.frame = {
  hidden = hidden,
  setallpoints = setAllPoints,
  framestrata = frameStrata,
  framelevel = numberSetter("SetFrameLevel"),
  enablemouse = boolSetter("EnableMouse"),
  movable = boolSetter("SetMovable"),
  toplevel = boolSetter("SetToplevel"),
  id = numberSetter("SetID"),
  alpha = numberSetter("SetAlpha"),
  scale = numberSetter("SetScale"),
  -- source: row W43 and W44 (xsd:1004-1007, :1034): Slider and StatusBar attributes; the xsd spells a fill style Standard,
  -- StandardNoRangeFill, Center or Reverse and SetFillStyle takes the upper case.
  orientation = stringSetter("SetOrientation"),
  valuestep = numberSetter("SetValueStep"),
  fillstyle = function(_, obj, _, value)
    return callIfPresent(obj, "SetFillStyle", value:upper())
  end,
  -- source: rows W35-W40 (xsd:1062-1064 and the EditBox attributes): EditBox attributes.
  multiline = boolSetter("SetMultiLine"),
  numeric = boolSetter("SetNumeric"),
  maxletters = numberSetter("SetMaxLetters"),
  autofocus = boolSetter("SetAutoFocus"),
  historylines = numberSetter("SetHistoryLines"),
  password = boolSetter("SetPassword"),
  mixin = mixin,
  securemixin = mixin,
  inherits = function(w, frame, _, value)
    TemplateApply.applyList(w, frame, value)
  end,
  parent = skip, -- built by XmlBuild.frame
  virtual = skip, -- XmlBuild.frame registers a virtual element as a template; its body carries the attribute
  intrinsic = skip, -- likewise for an intrinsic element, registered as a frame type (ui/xml_intrinsic.lua)
}

M.region = {
  hidden = hidden,
  setallpoints = setAllPoints,
  alpha = numberSetter("SetAlpha"),
  -- source: row X21 (ui.xsd LayoutFrameAttributes): regions take mixin and secureMixin as frames do; they have no OnLoad
  mixin = mixin,
  securemixin = mixin,
  virtual = skip, -- XmlBuild.region registers a virtual element as a template; its body carries the attribute
  -- source: wiki XML/Texture, "Lua Equivalent": file is SetTexture, atlas and useAtlasSize are SetAtlas
  file = stringSetter("SetTexture"),
  atlas = function(_, region, _, value, node)
    return callIfPresent(region, "SetAtlas", value, node.attrs.useatlassize == "true")
  end,
  useatlassize = skip, -- read by atlas
  alphamode = stringSetter("SetBlendMode"), -- row X17, assumed
  -- row X19, assumed: a global string's name gives that string, anything else is the text itself
  text = function(_, region, _, value)
    local global = rawget(_G, value)
    return callIfPresent(region, "SetText", type(global) == "string" and global or value)
  end,
  justifyh = stringSetter("SetJustifyH"),
  justifyv = stringSetter("SetJustifyV"),
  -- row X19, assumed: a font object's name
  inherits = function(w, region, _, value)
    BehaviourRegions.applyTemplates(w, region, value)
  end,
}

local function appliedBefore(a, b)
  local rankA, rankB = EARLY[a] or math.huge, EARLY[b] or math.huge
  if rankA ~= rankB then
    return rankA < rankB
  end
  return a < b
end

-- Applies node's attributes to obj with the setters in `set` (M.frame or M.region), reporting each unsupported one once
-- per file.
function M.apply(w, obj, node, session, set)
  local st = w.ui.state[obj]
  local names = {}
  for name in pairs(node.attrs) do
    if not M.IDENTITY[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names, appliedBefore)
  for _, name in ipairs(names) do
    local setter = set[name]
    if not setter or setter(w, obj, st, node.attrs[name], node, session) == false then
      session.report("attr:" .. name, "unsupported XML attribute '" .. name .. "' ignored")
    end
  end
end

return M

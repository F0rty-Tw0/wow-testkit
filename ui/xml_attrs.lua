-- XML attributes of frames and regions as setters: frame and region are tables of fn(w, obj, st, value, node, session)
-- keyed by the lowercased attribute name (the parser lowercases them). A setter that returns false could not apply the
-- attribute to this widget; a name with no setter is unsupported. Both are reported by apply. Identity attributes (name,
-- parentKey, parentArray) belong to ui/xml_build.lua.
local M = {}

local BehaviourRegions = require("ui.behaviour_regions")
local TemplateApply = require("ui.template_apply")
local Widgets = require("ui.widgets")

local IDENTITY = { name = true, parentkey = true, parentarray = true }
-- Applied before every other attribute, in this order; the rest follow by name.
local EARLY = { inherits = 1, mixin = 2, securemixin = 3 }

local function send(obj, method, ...)
  if obj[method] then
    obj[method](obj, ...)
    return true
  end
  return false
end

local function flag(method)
  return function(_, obj, _, value)
    return send(obj, method, value == "true")
  end
end

local function number(method)
  return function(_, obj, _, value)
    local n = tonumber(value)
    return n == nil or send(obj, method, n)
  end
end

local function text(method)
  return function(_, obj, _, value)
    return send(obj, method, value)
  end
end

local function skip() end

-- Created shown; no OnHide runs (row X7, the no-OnHide part assumed).
local function hidden(_, _, st, value)
  if value == "true" then
    st.shown = false
  end
end

local function setAllPoints(_, obj, _, value)
  return value ~= "true" or send(obj, "SetAllPoints")
end

-- source: wiki XML/LayoutFrame, `mixin` / `secureMixin` "Inherits a comma-separated list of Lua mixins". secureMixin is
-- copied the same way (its secure wrapping is not modelled); a name is recorded as templates record theirs, found or not.
local function mixin(_, frame, st, value, _, session)
  st.mixins = st.mixins or {}
  for name in value:gmatch("[^,%s]+") do
    st.mixins[#st.mixins + 1] = name
    local source = rawget(_G, name)
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
  framestrata = text("SetFrameStrata"),
  framelevel = number("SetFrameLevel"),
  enablemouse = flag("EnableMouse"),
  movable = flag("SetMovable"),
  toplevel = flag("SetToplevel"),
  id = number("SetID"),
  alpha = number("SetAlpha"),
  scale = number("SetScale"),
  mixin = mixin,
  securemixin = mixin,
  inherits = function(w, frame, _, value)
    Widgets.applyTemplateList(w, frame, value)
  end,
  parent = skip, -- built by XmlBuild.frame
  virtual = skip, -- XmlBuild.frame builds no virtual frame yet
}

M.region = {
  hidden = hidden,
  setallpoints = setAllPoints,
  alpha = number("SetAlpha"),
  -- source: wiki XML/Texture, "Lua Equivalent": file is SetTexture, atlas and useAtlasSize are SetAtlas
  file = text("SetTexture"),
  atlas = function(_, region, _, value, node)
    return send(region, "SetAtlas", value, node.attrs.useatlassize == "true")
  end,
  useatlassize = skip, -- read by atlas
  alphamode = text("SetBlendMode"), -- row X17, assumed
  -- row X19, assumed: a global string's name gives that string, anything else is the text itself
  text = function(_, region, _, value)
    local global = rawget(_G, value)
    return send(region, "SetText", type(global) == "string" and global or value)
  end,
  justifyh = text("SetJustifyH"),
  justifyv = text("SetJustifyV"),
  -- row X19, assumed: a font object's name
  inherits = function(w, region, _, value)
    BehaviourRegions.applyFontTemplates(w, region, value)
  end,
}

local function before(a, b)
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
    if not IDENTITY[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names, before)
  for _, name in ipairs(names) do
    local setter = set[name]
    if not setter or setter(w, obj, st, node.attrs[name], node, session) == false then
      session.report("attr:" .. name, "unsupported XML attribute '" .. name .. "' ignored")
    end
  end
end

return M

-- Hand-written alpha, scale, frame level and strata with the client's defaults: alpha and scale 1, effective
-- values multiplied down the parent chain, level one above the parent's (0 at the root), strata inherited from
-- the parent else MEDIUM. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Callsite = require("ui.callsite")

local methods = {}
M.methods = methods

local DEFAULT_STRATA = "MEDIUM"
local ROOT_LEVEL = 0

-- source: row V1, wiki Frame_Strata, "from back to front": BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN,
-- FULLSCREEN_DIALOG, TOOLTIP. WORLD is reserved for the world frame and cannot be assigned, so it stays out.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- source: confirmed Blizzard_SharedXML/UI.xsd:18-30 FRAMESTRATA: the STRATA names and BLIZZARD (which ranks as MEDIUM
-- here); tbc 70577 UI.xsd adds PARENT, inherit. Upper case.
M.FRAMESTRATA = { BLIZZARD = true, PARENT = true }
for name in pairs(STRATA) do
  M.FRAMESTRATA[name] = true
end

local function parentState(w, st)
  return st.parent and w.ui.state[st.parent]
end

-- The product of st[field] up the parent chain; a region with st[ignoreField] set is the last one multiplied.
local function chainProduct(w, st, field, ignoreField)
  local product = 1
  while st do
    product = product * (st[field] or 1)
    local ignoresParent = st[ignoreField]
    st = not ignoresParent and parentState(w, st) or nil
  end
  return product
end

local function frameLevel(w, st)
  if st.frameLevel then
    return st.frameLevel
  end
  local parent = parentState(w, st)
  return parent and frameLevel(w, parent) + 1 or ROOT_LEVEL
end

function methods.SetAlpha(_, _, st, alpha)
  st.alpha = alpha
end

function methods.GetAlpha(_, _, st)
  return st.alpha or 1
end

-- The product of alphas up the parent chain, stopping at a region with SetIgnoreParentAlpha (the stop point is assumed,
-- row W13).
function M.effectiveAlpha(w, obj)
  return chainProduct(w, w.ui.state[obj], "alpha", "ignoreAlpha")
end

function methods.GetEffectiveAlpha(w, obj)
  return M.effectiveAlpha(w, obj)
end

function methods.SetScale(_, _, st, scale)
  st.scale = scale
end

function methods.GetScale(_, _, st)
  return st.scale or 1
end

-- The product of scales up the parent chain, stopping at a region with SetIgnoreParentScale (assumed, row W13).
function M.effectiveScale(w, st)
  return chainProduct(w, st, "scale", "ignoreScale")
end

function methods.GetEffectiveScale(w, _, st)
  return M.effectiveScale(w, st)
end

-- source: row W77 (confirmed) wiki Frame_Strata: "When a parent frame changes its level, the descendant frames will change
-- levels respectively ... if a child frame was set 2 levels higher than its parent, it will shift 2 levels higher after
-- the parent moves. If this effect would cause a frame level to be lower than 0 it will instead be set to 10000."
-- A descendant without its own level follows its parent by default, so only the explicit ones shift.
local MAX_LEVEL = 10000

local function shiftDescendants(w, st, delta)
  for _, child in ipairs(st.children or {}) do
    local childState = w.ui.state[child]
    if childState then
      if childState.frameLevel then
        local level = childState.frameLevel + delta
        childState.frameLevel = level < 0 and MAX_LEVEL or level
      end
      shiftDescendants(w, childState, delta)
    end
  end
end

-- Sets st's level and moves every descendant by the same amount; SetFrameLevel, Raise and Lower all go through it.
function M.setFrameLevel(w, st, level)
  local delta = level - frameLevel(w, st)
  st.frameLevel = level
  shiftDescendants(w, st, delta)
end

function methods.SetFrameLevel(w, _, st, level)
  M.setFrameLevel(w, st, level)
end

function methods.GetFrameLevel(w, _, st)
  return frameLevel(w, st)
end

-- source: assumed (LY15, no Lua shows the C side) a name outside FRAMESTRATA raises at the caller and keeps the strata; any
-- case is taken, as SetPoint takes "Left" (retail blizzard_gluexml/mainline/characterservices.lua:501); PARENT
-- inherits, as the XML attribute does. A non-string is stored as given.
function methods.SetFrameStrata(_, _, st, strata)
  if type(strata) == "string" then
    if not M.FRAMESTRATA[strata:upper()] then
      error(string.format("SetFrameStrata: '%s' is not a FRAMESTRATA", strata), Callsite.level())
    end
    strata = strata:upper()
  end
  st.strata = strata ~= "PARENT" and strata or nil
end

function methods.GetFrameStrata(w, _, st)
  while st do
    if st.strata then
      return st.strata
    end
    st = parentState(w, st)
  end
  return DEFAULT_STRATA
end

-- The draw-order key of a frame, back to front: { strata rank, level, seq }. A strata outside STRATA (BLIZZARD,
-- a non-string) ranks as MEDIUM. render_order.lua sorts by it and LayoutHit.above compares it, so the
-- frame drawn on top is the one hit.
function M.frameKey(w, obj, st)
  local strata = methods.GetFrameStrata(w, obj, st)
  local key = { STRATA[strata] or STRATA[DEFAULT_STRATA], methods.GetFrameLevel(w, obj, st), st.seq }

  return key
end

return M

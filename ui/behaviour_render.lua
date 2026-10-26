-- Hand-written alpha, scale, frame level and strata with the client's defaults: alpha and scale 1, effective
-- values multiplied down the parent chain, level one above the parent's (0 at the root), strata inherited from
-- the parent else MEDIUM. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local methods = {}
M.methods = methods

local DEFAULT_STRATA = "MEDIUM"
local ROOT_LEVEL = 0

-- source: row V1, wiki Frame_Strata, "from back to front": BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN,
-- FULLSCREEN_DIALOG, TOOLTIP. WORLD is reserved for the world frame and cannot be assigned, so it stays out.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

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

function methods.SetFrameLevel(_, _, st, level)
  st.frameLevel = level
end

function methods.GetFrameLevel(w, _, st)
  return frameLevel(w, st)
end

function methods.SetFrameStrata(_, _, st, strata)
  st.strata = strata
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

-- The draw-order key of a frame, back to front: { strata rank, level, seq }. A strata outside STRATA (WORLD, a
-- misspelt or lowercase name) ranks as MEDIUM. render_order.lua sorts by it and LayoutHit.above compares it, so the
-- frame drawn on top is the one hit.
function M.frameKey(w, obj, st)
  local strata = methods.GetFrameStrata(w, obj, st)
  local key = { STRATA[strata] or STRATA[DEFAULT_STRATA], methods.GetFrameLevel(w, obj, st), st.seq }

  return key
end

return M

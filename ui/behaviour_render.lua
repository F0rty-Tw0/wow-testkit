-- Hand-written alpha, scale, frame level and strata with the client's defaults: alpha and scale 1, effective
-- values multiplied down the parent chain, level one above the parent's (0 at the root), strata inherited from
-- the parent else MEDIUM. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local methods = {}
M.methods = methods

local DEFAULT_STRATA = "MEDIUM"
local ROOT_LEVEL = 0

local function parentState(w, st)
  return st.parent and w.ui.state[st.parent]
end

local function chainProduct(w, st, field)
  local product = 1
  while st do
    product = product * (st[field] or 1)
    st = parentState(w, st)
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

function methods.GetEffectiveAlpha(w, _, st)
  return chainProduct(w, st, "alpha")
end

function methods.SetScale(_, _, st, scale)
  st.scale = scale
end

function methods.GetScale(_, _, st)
  return st.scale or 1
end

function methods.GetEffectiveScale(w, _, st)
  return chainProduct(w, st, "scale")
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

return M

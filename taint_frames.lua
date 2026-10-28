-- Protected frames and combat lockdown: which frames are protected (explicit from a Secure* template, implicit by
-- parenting or anchoring a protected frame to them), the guard ui/widgets.lua's bind calls through w.taint.guardMethod
-- for a method the docs flag protected, forbidden objects, and the methods IsProtected, CanChangeProtectedState and
-- IsForbidden.
local Callsite = require("ui.callsite")
local Protected = require("taint_protected")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local pairs, ipairs, error = pairs, ipairs, error
local format, tremove = string.format, table.remove

local methods = {}
M.methods = methods

-- source: assumed (row TS13) the methods a tainted caller may still call on a forbidden object.
local FORBIDDEN_OK = { IsForbidden = true, GetAttribute = true, SetAttribute = true }

-- The name a refusal prints: the frame's global name, else its object type (rows TS10, assumed for the type).
local function prefix(st, typeName)
  return st.name or typeName
end

-- Adds to set the parent and the anchor targets of frame, and of each frame added in turn.
local function spreadUp(w, set, frame)
  local pending = { frame }
  while #pending > 0 do
    local st = w.ui.state[tremove(pending)]
    local targets = { st and st.parent }
    for _, anchor in ipairs(st and st.points or {}) do
      targets[#targets + 1] = anchor[2]
    end
    for _, target in ipairs(targets) do
      if not set[target] and w.ui.state[target] then
        set[target] = true
        pending[#pending + 1] = target
      end
    end
  end
end

-- source: assumed (row TS12) the implicit rule; explicit protection is the template's (st.protected, set by
-- ui/template_apply.lua).
-- Returns isProtected, isProtectedExplicitly. Implicit protection is computed on each call from the parents and anchors of
-- every explicitly protected frame, so a reparent or a cleared anchor needs no invalidation.
function M.isProtected(w, frame)
  local st = w.ui.state[frame]
  if st.protected == true then
    return true, true
  end
  local implicit = {}
  for other, otherState in pairs(w.ui.state) do
    if otherState.protected == true then
      spreadUp(w, implicit, other)
    end
  end
  return implicit[frame] == true, false
end

-- source: assumed (row TS13) a tainted call on a forbidden object other than IsForbidden, GetAttribute and SetAttribute
-- raises a Lua error, no event; the message text is the kit's.
local function refuseForbidden(st, typeName, method)
  if FORBIDDEN_OK[method] then
    return
  end
  local message = "Attempt to access forbidden object '%s'. Consider using IsForbidden to prevent this error."
  error(format(message, prefix(st, typeName)), Callsite.level())
end

-- True when a tainted call of method on frame was refused. ui/widgets.lua calls it for a forbidden frame and for a method
-- the docs flag protected (plan.methods[method].protected) while the world is in combat; the flag is read again here for
-- the forbidden case. A tainted call to a flagged method on a protected frame in combat reports ADDON_ACTION_BLOCKED and
-- is refused; secure callers pass.
function M.guardMethod(w, frame, typeName, method)
  local t = w.taint
  if not t.enforce or not Taint.current(w) then
    return false
  end
  local st = w.ui.state[frame]
  if st.forbidden then
    refuseForbidden(st, typeName, method)
    return false
  end
  local entry = st.plan.methods[method]
  if not (entry and entry.protected and w.mock and w.mock.combat == true and M.isProtected(w, frame)) then
    return false
  end
  Protected.report(w, "BLOCKED", prefix(st, typeName) .. ":" .. method .. "()")
  return true
end

-- Marks frame forbidden (or not): a tainted caller may then call only IsForbidden, GetAttribute and SetAttribute on it.
function M.setForbidden(w, frame, forbidden)
  w.ui.state[frame].forbidden = forbidden and true or nil
end

function methods.IsProtected(w, obj)
  return M.isProtected(w, obj)
end

-- source: assumed (row TS12) true for an unprotected frame; for a protected one only out of combat, or for secure code.
function methods.CanChangeProtectedState(w, obj)
  local tainted = Taint.current(w) ~= nil
  local combat = w.mock ~= nil and w.mock.combat == true
  return not (tainted and combat and M.isProtected(w, obj))
end

function methods.IsForbidden(_, _, st)
  return st.forbidden == true
end

function M.install(w)
  w.taint.guardMethod, w.taint.isProtected = M.guardMethod, M.isProtected
end

return M

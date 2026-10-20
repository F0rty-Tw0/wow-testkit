-- Frame attributes: any Lua value per case-insensitive name. SetAttribute fires OnAttributeChanged on frame types
-- that list the handler. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Callsite = require("ui.callsite")
local Scripts = require("ui.scripts")

local methods = {}
M.methods = methods

-- The doc types SetAttribute's value as cstring; the client stores anything. Read by lenient in ui/widgets.lua.
M.uncheckedArgs = { SetAttribute = { value = true } }

-- source: wiki API_Frame_SetAttribute, attributeName "(case-insensitive)". A nil name raises at the caller's line
-- (row A3, assumed: the client's message is unsourced); other non-strings are left to the doc check.
local function keyOf(method, name)
  if name == nil then
    error(method .. ": attributeName must be a string", Callsite.level())
  end
  return type(name) == "string" and name:lower() or name
end

function methods.SetAttribute(w, obj, st, name, value)
  local key = keyOf("SetAttribute", name)
  st.attributes = st.attributes or {}
  st.attributes[key] = value
  -- source: wiki UIHANDLER_OnAttributeChanged, "(self, name, value)", name "The lowercased name"
  if Scripts.supports(st.plan.type, "OnAttributeChanged", w.flavor) then
    w:callScript(obj, "OnAttributeChanged", key, value)
  end
end

function methods.GetAttribute(_, _, st, name)
  local key = keyOf("GetAttribute", name)
  return st.attributes and st.attributes[key]
end

return M

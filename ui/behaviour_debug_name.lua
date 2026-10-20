-- GetDebugName (row F3, wiki API_Object_GetDebugName): a named object's name; an anonymous one with a parent is
-- "<parent's debug name>.<key>", the key being the parent's field holding it, else its address; an anonymous one
-- without a parent is "". Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local methods = {}
M.methods = methods

-- The first string key under which parent holds obj, or nil.
local function keyIn(parent, obj)
  if type(parent) ~= "table" then
    return nil
  end
  for key, value in pairs(parent) do
    if value == obj and type(key) == "string" then
      return key
    end
  end

  return nil
end

-- source: assumed (row F3) the client prints a memory address ("156f1390860"); the kit prints the table's address,
-- in lowercase hex without leading zeros.
local function address(obj)
  local hex = tostring(obj):match("(%x+)$"):gsub("^0+", "")

  return hex:lower()
end

-- source: confirmed (row F3); preferParentKey is ignored (no source shows what it changes).
local function debugName(w, obj, st)
  if st.name then
    return st.name
  end
  local parent = st.parent
  if parent == nil then
    return ""
  end
  local parentState = w.ui.state[parent]
  local parentName = parentState and debugName(w, parent, parentState) or ""
  local key = keyIn(parent, obj) or address(obj)

  return parentName .. "." .. key
end

methods.GetDebugName = debugName

return M

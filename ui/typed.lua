-- Type-specific method registry. Behaviour.typed (ui/behaviour_input.lua) holds one function per method name, so two
-- types that each own a body for the same name register through Typed.add, which keeps the earlier registrants.
local M = {}

local BehaviourInput = require("ui.behaviour_input")

-- Registers impl as the body of name for the types whose plan.isA has the (lowercase) ancestor isA; any other type gets
-- the answer of what was registered before, else nil (the name-keyed or generic body).
function M.add(name, isA, impl)
  local previous = BehaviourInput.typed[name]
  BehaviourInput.typed[name] = function(plan)
    if plan.isA[isA] then
      return impl
    end
    if not previous then
      return nil
    end

    return previous(plan)
  end
end

return M

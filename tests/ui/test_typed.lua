-- Typed.add: one Behaviour.typed entry per method name, answering for every type registered under it.
local A = require("assert")
local Behaviour = require("ui.behaviour")
local Typed = require("ui.typed")

local function planOf(...)
  local isA = {}
  for _, name in ipairs({ ... }) do
    isA[name] = true
  end

  return { isA = isA }
end

local function test_a_name_registered_for_two_types_answers_for_both()
  local forA = function() end
  local forB = function() end
  Typed.add("TypedProbe", "a", forA)
  Typed.add("TypedProbe", "b", forB)
  A.eq(Behaviour.typed.TypedProbe(planOf("a")), forA)
  A.eq(Behaviour.typed.TypedProbe(planOf("b")), forB)
  A.eq(Behaviour.typed.TypedProbe(planOf("c")), nil)
end

local function test_the_latest_registration_wins_for_a_type_they_share()
  local first = function() end
  local second = function() end
  Typed.add("TypedShared", "a", first)
  Typed.add("TypedShared", "a", second)
  A.eq(Behaviour.typed.TypedShared(planOf("a")), second)
end

return function()
  test_a_name_registered_for_two_types_answers_for_both()
  test_the_latest_registration_wins_for_a_type_they_share()
end

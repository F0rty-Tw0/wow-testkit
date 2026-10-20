-- getfenv and setfenv misuse in addon code: errors name the function and the addon's line as with Lua 5.1's C
-- functions, a call in tail position that loses the caller says so, and kit functions keep their environment
-- (docs/client-sources.md L3, L4).
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.world")
local fs = require("fs")

-- Loads a one-file retail addon whose Core.lua is source; returns its ns and its recorded error messages.
local function loadSource(name, source)
  local root = Tmp.dir("addon") .. "/" .. name
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. name .. ".toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  local ns, messages = nil, {}
  H.withWorld("retail", function(w)
    ns = Addon.load(w, { name = name, root = root })
    for i, entry in ipairs(w.errors) do
      messages[i] = tostring(entry.message)
    end
  end)
  return ns, messages
end

local ARGUMENT_ERRORS = [[
local _, ns = ...
ns.noArgs = select(2, pcall(function() setfenv() end))
ns.oneArg = select(2, pcall(function() setfenv(1) end))
ns.badLevel = select(2, pcall(function() local _ = getfenv(100) end))
]]

local function test_fenv_argument_errors_name_the_function_and_the_addon_line()
  local ns, messages = loadSource("FenvArgs", ARGUMENT_ERRORS)
  A.same({ messages, ns.noArgs, ns.oneArg, ns.badLevel }, {
    {},
    "addon:FenvArgs/Core.lua:2: bad argument #2 to 'setfenv' (table expected, got no value)",
    "addon:FenvArgs/Core.lua:3: bad argument #2 to 'setfenv' (table expected, got no value)",
    "addon:FenvArgs/Core.lua:4: bad argument #1 to 'getfenv' (invalid level)",
  })
end

local TAIL_CALLS = [[
local _, ns = ...
local function tailSet() return setfenv(1, {}) end
local function tailGet() return getfenv() end
ns.tailSet = select(2, pcall(tailSet))
ns.tailGet = select(2, pcall(tailGet))
]]

-- Lua 5.1 keeps the caller of a C function in tail position; the kit's Lua getfenv/setfenv replace it, so the
-- function whose environment level 1 names is gone (known gap, L3/L4).
local function test_level_1_fenv_calls_in_tail_position_raise_that_the_caller_is_lost()
  local ns, messages = loadSource("FenvTail", TAIL_CALLS)
  A.same({ messages, ns.tailSet, ns.tailGet }, {
    {},
    "'setfenv' cannot reach the calling function: a tail call (return setfenv(...)) replaced it",
    "'getfenv' cannot reach the calling function: a tail call (return getfenv(...)) replaced it",
  })
end

local COROUTINE_BODIES = [[
local _, ns = ...
ns.get = select(2, pcall(coroutine.wrap(getfenv)))
ns.set = select(2, pcall(coroutine.wrap(setfenv), 1, {}))
]]

-- Lua 5.1 refuses a C function as a coroutine body; the kit's getfenv/setfenv are Lua functions, so they run with
-- no caller at all, and level 1 is an invalid level as for any level past the stack.
local function test_level_1_fenv_calls_as_a_coroutine_body_raise_invalid_level()
  local ns, messages = loadSource("FenvCoroutine", COROUTINE_BODIES)
  A.same({ messages, ns.get, ns.set }, {
    {},
    "bad argument #1 to 'getfenv' (invalid level)",
    "bad argument #1 to 'setfenv' (invalid level)",
  })
end

local KIT_FUNCTIONS = [[
local _, ns = ...
ns.byFunction, ns.kitFunction = select(2, pcall(function() setfenv(CreateFrame, {}) end)), CreateFrame
function FenvHooked() ns.byLevel = select(2, pcall(setfenv, 3, {})) end
hooksecurefunc("FenvHooked", function() end)
FenvHooked()
setfenv(2, {})
]]

-- The client's API functions are C functions: setfenv raises for them. The kit refuses every function whose
-- environment is the host's _G, and so every kit function, named directly or by level (here level 3 under pcall is
-- hooksecurefunc's wrapper). Known gap: the kit reaches addon code through a tail call, so level 2 from a file's
-- main chunk is a lost frame, where the client has its C loader.
local function test_setfenv_refuses_kit_functions_like_the_clients_c_functions()
  local hostG, ns, messages = _G, loadSource("FenvKit", KIT_FUNCTIONS)
  local refused = "'setfenv' cannot change environment of given object"
  A.same({ messages, ns.byFunction, ns.byLevel }, {
    { "addon:FenvKit/Core.lua:6: no function environment for tail call at level 2" },
    "addon:FenvKit/Core.lua:2: " .. refused,
    refused,
  })
  A.eq(getfenv(ns.kitFunction), hostG)
end

return function()
  test_fenv_argument_errors_name_the_function_and_the_addon_line()
  test_level_1_fenv_calls_in_tail_position_raise_that_the_caller_is_lost()
  test_level_1_fenv_calls_as_a_coroutine_body_raise_invalid_level()
  test_setfenv_refuses_kit_functions_like_the_clients_c_functions()
end

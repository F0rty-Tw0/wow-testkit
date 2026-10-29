-- An addon can clear or reassign globals such as select, xpcall and type; the kit functions it calls afterwards must
-- still work.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local HF = require("tests.helpers.framexml")
local fs = require("fs")

local CLEARS_THEN_CALLS = [[
local _, ns = ...
select, xpcall = nil, nil
function ClearedHookTarget() end
hooksecurefunc("ClearedHookTarget", function() ns.hooked = true end)
ClearedHookTarget()
ns.name = UnitName("player")
local button = CreateFrame("Button")
button:RegisterForClicks("AnyUp", "AnyDown")
ns.shown = button:IsShown()
ns.bor = bit.bor(1, 2, 4)
ns.utf8 = strlenutf8("ab")
ns.menu = MenuUtil.CreateContextMenu(nil, function(_, root) root:CreateButton("Entry") end) ~= nil
ns.mixed = Mixin({}, { a = 1 }).a
]]

local function test_kit_functions_still_work_after_an_addon_clears_select_and_xpcall()
  local root = Tmp.dir("addon") .. "/Cleared"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Cleared.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", CLEARS_THEN_CALLS)
  local errors, seen = {}, nil
  HF.withFrameXML("retail", function(w)
    local ns = Addon.load(w, { name = "Cleared", root = root })
    for i, entry in ipairs(w.errors) do
      errors[i] = tostring(entry.message)
    end
    seen = { ns.hooked, type(ns.name), ns.shown, ns.bor, ns.utf8, ns.menu, ns.mixed }
  end)
  A.same({ errors, seen }, { {}, { true, "string", true, 7, 2, true, 1 } })
end

-- Loads addon "Typed" (Core.lua = source) in a retail scenario, logs in, calls ns.run, advances a second, then calls
-- after(s) when given (kit code, while the world still runs). Returns the namespace and the world's recorded error
-- messages; a failure carries those messages.
local function runAddon(source, after)
  local root = Tmp.dir("addon") .. "/Typed"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Typed.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  local s = Scenario.new({ addon = "Typed", root = root, flavor = "retail" })
  local ok, err = pcall(function()
    s:login()
    s.ns.run()
    s:advance(1)
    if after then
      after(s)
    end
  end)
  local errors = {}
  for i, entry in ipairs(s.w.errors) do
    errors[i] = tostring(entry.message)
  end
  local ns = s.ns
  s.w:destroy()
  if not ok then
    error(tostring(err) .. " ERRS: " .. table.concat(errors, " | "), 0)
  end
  return ns, errors
end

-- ns.run exercises the kit paths that read bare `type`: layout, text, status bar, timers.
local CALLS_KIT = [[
ns.run = function()
  local f = CreateFrame("Frame", "TypedF")
  f:SetPoint("CENTER")
  f:SetAllPoints()
  f:CreateFontString():SetText("hi")
  CreateFrame("StatusBar"):SetValue(1)
  C_Timer.After(0.5, function() ns.timer = true end)
end
]]

local function test_kit_functions_still_work_after_an_addon_clears_type()
  local ns, errors = runAddon("local _, ns = ...\ntype = nil\nns.sees = type\n" .. CALLS_KIT)
  A.same({ errors, tostring(ns.sees), ns.timer }, { {}, "nil", true })
end

local function test_kit_functions_still_work_after_an_addon_assigns_a_string_to_type()
  local ns, errors = runAddon("local _, ns = ...\ntype = 'spell'\nns.sees = type\n" .. CALLS_KIT)
  A.same({ errors, ns.sees, ns.timer }, { {}, "spell", true })
end

local function test_a_cleared_name_stays_cleared_for_rawget_and_pairs_assumed()
  local ns = runAddon([[
local _, ns = ...
rawset(_G, "type", nil)
ns.raw = rawget(_G, "type")
ns.listed = false
for k in pairs(_G) do
  if k == "type" then ns.listed = true end
end
ns.run = function() end
]])
  A.same({ tostring(ns.raw), ns.listed }, { "nil", false })
end

-- rawset has a view override: an addon's own rawset replaces it, and the override it captured still keeps the write.
local function test_an_addon_rawset_wrapping_the_original_still_clears_type()
  local ns, errors = runAddon([[
local _, ns = ...
local original = rawset
rawset = function(t, k, v)
  ns.wrapped = k
  return original(t, k, v)
end
rawset(_G, "type", nil)
ns.sees = type
]] .. CALLS_KIT)
  A.same({ errors, ns.wrapped, tostring(ns.sees), ns.timer }, { {}, "type", "nil", true })
end

-- hooksecurefunc on a base-library name hooks the addon view's value: the addon's calls fire the hook, kit code's don't.
local function test_a_hooked_base_library_name_fires_for_the_addons_calls_only()
  local ns, errors = runAddon([[
local _, ns = ...
ns.calls, ns.hooks = 0, 0
local original = type
type = function(v) ns.calls = ns.calls + 1; return original(v) end
hooksecurefunc("type", function() ns.hooks = ns.hooks + 1 end)
hooksecurefunc(_G, "tostring", function() ns.hooks = ns.hooks + 10 end)
ns.sees = type(1) .. tostring(2)
tostring = nil
ns.cleared = tostring
]] .. CALLS_KIT)
  A.same({ errors, ns.sees, ns.calls, ns.hooks, tostring(ns.cleared), ns.timer }, { {}, "number2", 1, 11, "nil", true })
end

-- A false written to a base-library name reads back as false, apart from a cleared (nil) one, as on any table.
local function test_a_false_written_to_a_base_library_name_reads_back_as_false()
  local ns, errors = runAddon([[
local _, ns = ...
type = false
ns.sees, ns.raw = type, rawget(_G, "type")
for k, v in pairs(_G) do
  if k == "type" then ns.listed = v end
end
type = nil
ns.cleared = type
]] .. CALLS_KIT)
  A.same({ errors, ns.sees, ns.raw, ns.listed, tostring(ns.cleared), ns.timer }, { {}, false, false, false, "nil", true })
end

-- hooksecurefunc(_G, name, hook) given the _G addon code sees hooks the global itself, as the name-only form does: kit
-- code calling the global fires the hook too.
local function test_a_hook_through_the_g_view_fires_for_kit_callers_too()
  local ns, errors = runAddon(
    [[
local _, ns = ...
ns.hooks = 0
function TKViewHooked() return "original" end
hooksecurefunc(_G, "TKViewHooked", function() ns.hooks = ns.hooks + 1 end)
ns.run = function() ns.result = TKViewHooked() end
]],
    function()
      _G.TKViewHooked()
    end
  )
  A.same({ errors, ns.result, ns.hooks }, { {}, "original", 2 })
end

return function()
  test_kit_functions_still_work_after_an_addon_clears_select_and_xpcall()
  test_kit_functions_still_work_after_an_addon_clears_type()
  test_kit_functions_still_work_after_an_addon_assigns_a_string_to_type()
  test_a_cleared_name_stays_cleared_for_rawget_and_pairs_assumed()
  test_an_addon_rawset_wrapping_the_original_still_clears_type()
  test_a_hooked_base_library_name_fires_for_the_addons_calls_only()
  test_a_false_written_to_a_base_library_name_reads_back_as_false()
  test_a_hook_through_the_g_view_fires_for_kit_callers_too()
end

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

-- Loads addon "Typed" (Core.lua = source) in a retail scenario, logs in, calls ns.run and advances a second.
-- Returns the namespace and the world's recorded error messages; a failure carries those messages.
local function runAddon(source)
  local root = Tmp.dir("addon") .. "/Typed"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Typed.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  local s = Scenario.new({ addon = "Typed", root = root, flavor = "retail" })
  local ok, err = pcall(function()
    s:login()
    s.ns.run()
    s:advance(1)
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

return function()
  test_kit_functions_still_work_after_an_addon_clears_select_and_xpcall()
  test_kit_functions_still_work_after_an_addon_clears_type()
  test_kit_functions_still_work_after_an_addon_assigns_a_string_to_type()
  test_a_cleared_name_stays_cleared_for_rawget_and_pairs_assumed()
  test_an_addon_rawset_wrapping_the_original_still_clears_type()
end

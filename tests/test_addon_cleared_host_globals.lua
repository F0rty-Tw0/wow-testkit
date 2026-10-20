-- Addon writes land raw in _G, so an addon can clear host globals such as select and xpcall; the kit functions it
-- calls afterwards must still work.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
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

return function()
  test_kit_functions_still_work_after_an_addon_clears_select_and_xpcall()
end

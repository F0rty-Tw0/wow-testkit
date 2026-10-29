-- C_AddOns.LoadAddOn with the Blizzard UI layer on: what a runtime load leaves behind (blizzard_ui.lua M.loadOne). Every
-- extract is a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")

local TARGETS = { "Blizzard_MiniBase" }

-- A handler an addon set before LoadAddOn stays its handler; one the Blizzard addon sets while it loads is undone.
local function test_a_runtime_load_keeps_the_handler_the_caller_set()
  local addons = B.mini({ blizzard_miniwindow = { files = { ["miniwindow.lua"] = "seterrorhandler(function() end)\n" } } })
  B.run(addons, { targets = TARGETS }, function()
    local function mine() end
    _G.seterrorhandler(mine)
    A.eq(_G.C_AddOns.LoadAddOn("Blizzard_MiniWindow"), true)
    A.eq(_G.geterrorhandler(), mine)
  end)
end

return function()
  test_a_runtime_load_keeps_the_handler_the_caller_set()
end

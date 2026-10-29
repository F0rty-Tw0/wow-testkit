-- C_AddOns.LoadAddOn with the Blizzard UI layer on: what a runtime load leaves behind (blizzard_ui.lua M.loadOne). Every
-- extract is a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local BlizzardUi = require("blizzard_ui")
local G = require("tests.helpers.game")

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

-- source: assumed (row G15) a Blizzard_ addon the scenario scripts answers as scripted with the layer on too: its
-- DISABLED, or loaded as it stands without a folder, wins over the extract.
local function test_a_scripted_blizzard_addon_answers_as_scripted_with_the_layer_on_assumed()
  local function before(s)
    s.w:setMock({ addons = { Blizzard_MiniWindow = { enabled = false }, Blizzard_Kit = {} } })
  end
  B.run(B.mini(), { targets = TARGETS, before = before }, function()
    A.same({ _G.C_AddOns.LoadAddOn("Blizzard_MiniWindow") }, { nil, "DISABLED" })
    A.eq(_G.MiniWindowFrame, nil) -- not loaded from the extract
    A.eq(_G.C_AddOns.LoadAddOn("Blizzard_Kit"), true)
  end)
end

-- source: assumed (row G16) a Blizzard_ addon neither the extract nor the scenario holds answers MISSING and counts
-- unscripted, as with the layer off; with no extract, a scripted one still answers as scripted.
local function test_a_blizzard_addon_the_layer_lacks_falls_back_to_the_catalog_assumed()
  B.run(B.mini(), { targets = TARGETS }, function(s)
    A.same({ _G.C_AddOns.LoadAddOn("Blizzard_Nope") }, { nil, "MISSING" })
    A.eq(s.w.unscripted["C_AddOns.LoadAddOn"], 1)
  end)
  G.withGame("retail", function(w)
    BlizzardUi.load(w, nil)
    w:setMock({ addons = { Blizzard_Kit = {} } })
    A.eq(_G.C_AddOns.LoadAddOn("Blizzard_Kit"), true)
  end)
end

return function()
  test_a_runtime_load_keeps_the_handler_the_caller_set()
  test_a_scripted_blizzard_addon_answers_as_scripted_with_the_layer_on_assumed()
  test_a_blizzard_addon_the_layer_lacks_falls_back_to_the_catalog_assumed()
end

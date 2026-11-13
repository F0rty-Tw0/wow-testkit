-- Blizzard UI layer: a LoadOnDemand addon's `[Bootstrap]` TOC lines run at login, before the addon loads; LoadAddOn
-- then runs the rest and skips them (row BU30). Kit-authored mini extract (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Toc = require("toc")

local BOOT_TOC = "## Interface: 120100\n## LoadOnDemand: 1\nBlizzard_MiniBoot_Bootstrap.lua [Bootstrap]\n"
  .. "MiniBootClassic.lua [Bootstrap] [AllowLoadGameType classic]\nMiniBoot.lua\n"

local function mini()
  return B.mini({
    blizzard_miniboot = {
      toc = BOOT_TOC,
      files = {
        ["blizzard_miniboot_bootstrap.lua"] = "local name = ...\nMiniBootRuns = (MiniBootRuns or 0) + 1\n"
          .. "function MiniBoot_LoadUI() return C_AddOns.LoadAddOn(name) end\n",
        ["minibootclassic.lua"] = "MiniBootClassic = true\n",
        ["miniboot.lua"] = "MiniBootLoaded = true\n",
      },
    },
  })
end

-- source: confirmed (row BU30) wiki TOC_format "[Bootstrap] Restricts the addon directive or file to the bootstrap
-- process for LoadOnDemand addons"; assumed: the bootstrap runs at login and LoadAddOn does not run it again.
local function test_bootstrap_line_runs_at_login_and_load_runs_the_rest_once()
  B.run(mini(), { targets = { "Blizzard_MiniBase" } }, function(s)
    A.same({ _G.MiniBootRuns, _G.MiniBootClassic, _G.MiniBootLoaded }, { 1, nil, nil })
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniBase" })
    A.same(s.w.blizzard.errors, {})
    _G.MiniBoot_LoadUI()
    A.same({ _G.MiniBootRuns, _G.MiniBootLoaded }, { 1, true })
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniBase", "Blizzard_MiniBoot" })
  end)
end

local function test_bootstrap_line_keeps_its_game_type_bracket()
  B.run(mini(), { targets = { "Blizzard_MiniBase" }, flavor = "tbc" }, function()
    A.same({ _G.MiniBootRuns, _G.MiniBootClassic }, { 1, true })
  end)
end

local function bootAddon(lua)
  return { toc = "## LoadOnDemand: 1\nBoot.lua [Bootstrap]\n", files = { ["boot.lua"] = lua } }
end

-- source: assumed (row BU30) bootstrap code is Blizzard's, so its errors are the layer's.
local function test_a_bootstrap_error_goes_to_the_layer_report_assumed()
  B.run(B.mini({ blizzard_minibooterr = bootAddon("error('boot boom')\n") }), { targets = { "Blizzard_MiniBase" } }, function(s)
    local errors = s.w.blizzard.errors
    A.eq(#errors, 1)
    A.eq(tostring(errors[1].message):find("boot boom", 1, true) ~= nil, true)
  end)
end

-- source: assumed (row BU30) a bootstrap's seterrorhandler does not take the next bootstrap's errors from the layer
-- (folder order: minibooth runs before minibootz).
local function test_a_bootstrap_error_handler_ends_with_its_bootstrap_assumed()
  local addons = B.mini({
    blizzard_minibooth = bootAddon("seterrorhandler(function() MiniBootCaught = true end)\n"),
    blizzard_minibootz = bootAddon("error('boot boom')\n"),
  })
  B.run(addons, { targets = { "Blizzard_MiniBase" } }, function(s)
    A.eq(_G.MiniBootCaught, nil)
    A.eq(#s.w.blizzard.errors, 1)
  end)
end

-- source: assumed (row BU30) an addon that loads at login runs its [Bootstrap] lines with the rest, in TOC order.
local function test_bootstrap_lines_of_an_addon_that_loads_at_login_load_with_it_assumed()
  local parsed = Toc.parse("Boot.lua [Bootstrap]\nMain.lua\n")
  A.same({ (Toc.filesFor(parsed, "retail")) }, { { "Boot.lua", "Main.lua" } })
  A.same(Toc.bootstrapFiles(parsed, "retail"), {})
  local lod = Toc.parse("## LoadOnDemand: 1\n" .. "Boot.lua [Bootstrap]\nMain.lua\n")
  A.same({ (Toc.filesFor(lod, "retail")) }, { { "Main.lua" } })
  A.same(Toc.bootstrapFiles(lod, "retail"), { "Boot.lua" })
  A.same(select(2, Toc.filesFor(lod, "retail")), {}) -- [Bootstrap] is read, not reported as ignored
end

return function()
  test_bootstrap_line_runs_at_login_and_load_runs_the_rest_once()
  test_bootstrap_line_keeps_its_game_type_bracket()
  test_a_bootstrap_error_goes_to_the_layer_report_assumed()
  test_a_bootstrap_error_handler_ends_with_its_bootstrap_assumed()
  test_bootstrap_lines_of_an_addon_that_loads_at_login_load_with_it_assumed()
end

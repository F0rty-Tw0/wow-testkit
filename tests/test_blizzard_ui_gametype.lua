-- Blizzard UI layer: an addon whose TOC header `## AllowLoadGameType:` excludes the flavor does not load, whoever lists it
-- as a dependency (row BU8). Kit-authored mini extract (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")

local function mini(header)
  return B.mini({
    blizzard_minilab = {
      toc = "## Interface: 120100\n" .. header .. "MiniLab.lua\n",
      files = { ["minilab.lua"] = "MiniLabLoads = (MiniLabLoads or 0) + 1" },
    },
    blizzard_miniuser = {
      toc = "## Interface: 120100\n## OptionalDeps: Blizzard_MiniLab\nMiniUser.lua\n",
      files = { ["miniuser.lua"] = "MiniUserLoaded = true" },
    },
  })
end

-- source: assumed (row BU8) the header names the game types the addon loads on, as the per-file directive does (L1).
local function test_header_game_type_excluding_the_flavor_keeps_the_addon_out_assumed()
  B.run(mini("## AllowLoadGameType: plunderstorm\n"), { targets = { "Blizzard_MiniUser" } }, function(s)
    A.same({ s.w.blizzard.loaded, _G.MiniLabLoads, _G.MiniUserLoaded }, { { "Blizzard_MiniUser" }, nil, true })
    A.same(s.w.blizzard.skipped, { { name = "Blizzard_MiniLab", reason = "game type" } })
  end)
end

local function test_header_game_type_naming_the_flavor_loads_the_addon_assumed()
  B.run(mini("## AllowLoadGameType: mainline, cata\n"), { targets = { "Blizzard_MiniUser" } }, function(s)
    A.same({ s.w.blizzard.loaded, _G.MiniLabLoads }, { { "Blizzard_MiniLab", "Blizzard_MiniUser" }, 1 })
  end)
end

local function test_header_game_type_that_excludes_a_classic_flavor_applies_per_flavor_assumed()
  B.run(mini("## AllowLoadGameType: mainline\n"), { targets = { "Blizzard_MiniUser" }, flavor = "tbc" }, function(s)
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniUser" })
  end)
end

-- source: confirmed (row BU26) `## AllowLoad: Glue` keeps a login-screen addon out of the game UI, as a dependency too.
local function test_header_allow_load_glue_keeps_the_addon_out_of_the_game()
  B.run(mini("## AllowLoad: Glue\n"), { targets = { "Blizzard_MiniUser" } }, function(s)
    A.same({ s.w.blizzard.loaded, _G.MiniLabLoads }, { { "Blizzard_MiniUser" }, nil })
    A.same(s.w.blizzard.skipped, { { name = "Blizzard_MiniLab", reason = "glue screen" } })
  end)
end

local function test_header_allow_load_game_or_both_loads_the_addon()
  for _, header in ipairs({ "## AllowLoad: game\n", "## AllowLoad: Both\n" }) do
    B.run(mini(header), { targets = { "Blizzard_MiniUser" } }, function(s)
      A.same(s.w.blizzard.loaded, { "Blizzard_MiniLab", "Blizzard_MiniUser" }, header)
    end)
  end
end

-- source: assumed (row BU26) an inline game-type bracket on the header limits the directive itself to those game types.
local function test_header_allow_load_with_a_game_type_bracket_applies_only_there_assumed()
  local addons = mini("## AllowLoad: Glue [AllowLoadGameType classic]\n")
  B.run(addons, { targets = { "Blizzard_MiniUser" } }, function(s)
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniLab", "Blizzard_MiniUser" }) -- retail: no AllowLoad
  end)
  B.run(addons, { targets = { "Blizzard_MiniUser" }, flavor = "tbc" }, function(s)
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniUser" })
  end)
end

return function()
  test_header_game_type_excluding_the_flavor_keeps_the_addon_out_assumed()
  test_header_game_type_naming_the_flavor_loads_the_addon_assumed()
  test_header_game_type_that_excludes_a_classic_flavor_applies_per_flavor_assumed()
  test_header_allow_load_glue_keeps_the_addon_out_of_the_game()
  test_header_allow_load_game_or_both_loads_the_addon()
  test_header_allow_load_with_a_game_type_bracket_applies_only_there_assumed()
end

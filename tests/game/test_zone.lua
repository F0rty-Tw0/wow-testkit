-- Zone texts, guild counts and the C_Map reads, all from w.mock.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local function test_zone_texts_default_to_empty_strings() -- (G14)
  G.withGame("retail", function()
    A.same({ _G.GetZoneText(), _G.GetRealZoneText(), _G.GetSubZoneText(), _G.GetMinimapZoneText() }, { "", "", "", "" })
  end)
end

local function test_zone_texts_follow_the_mock_and_fall_back_assumed() -- (G14)
  G.withGame("retail", function(w)
    w:setMock({ zone = { zone = "Elwynn Forest", sub = "Goldshire" } })
    A.same(
      { _G.GetZoneText(), _G.GetSubZoneText(), _G.GetRealZoneText(), _G.GetMinimapZoneText() },
      { "Elwynn Forest", "Goldshire", "Elwynn Forest", "Goldshire" }
    )
    w:setMock({ zone = { real = "Elwynn", minimap = "Lion's Pride Inn" } })
    A.same({ _G.GetRealZoneText(), _G.GetMinimapZoneText() }, { "Elwynn", "Lion's Pride Inn" })
    w:setMock({ zone = { sub = "", minimap = false } })
    A.same({ _G.GetSubZoneText(), _G.GetMinimapZoneText() }, { "", "Elwynn Forest" })
  end)
end

local function test_guild_member_counts() -- (G14)
  G.withGame("retail", function(w)
    A.same({ _G.GetNumGuildMembers() }, { 0, 0 })
    w:setMock({ guild = { total = 40, online = 7 } })
    A.same({ _G.GetNumGuildMembers() }, { 40, 7 })
  end)
end

local function test_c_map_reads_the_zone_map() -- (G14)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      A.eq(_G.C_Map.GetBestMapForUnit("player"), nil, flavor)
      w:setMock({
        zone = { zone = "Elwynn Forest", mapID = 37 },
        maps = { [37] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13, flags = 0 } },
      })
      A.same({ _G.C_Map.GetBestMapForUnit("player"), _G.C_Map.GetBestMapForUnit("target") }, { 37 }, flavor)
      A.same(_G.C_Map.GetMapInfo(37), { mapID = 37, name = "Elwynn Forest", mapType = 3, parentMapID = 13, flags = 0 }, flavor)
      A.same({ _G.C_Map.GetMapInfo(999) }, {}, flavor)
      A.eq(w.unscripted["C_Map.GetMapInfo"], 1, flavor)
    end)
  end
end

local function test_map_without_a_parent_gives_zero() -- (G14)
  G.withGame("retail", function(w)
    w:setMock({ maps = { [947] = { name = "Azeroth", mapType = 2 } } })
    A.eq(_G.C_Map.GetMapInfo(947).parentMapID, 0)
  end)
end

return function()
  test_zone_texts_default_to_empty_strings()
  test_zone_texts_follow_the_mock_and_fall_back_assumed()
  test_guild_member_counts()
  test_c_map_reads_the_zone_map()
  test_map_without_a_parent_gives_zero()
end

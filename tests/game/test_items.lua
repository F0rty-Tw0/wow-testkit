-- Item info, counts, money and specialization, all read from w.mock.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local LINK = "|cffffffff|Hitem:6948::::::::::::|h[Hearthstone]|h|r"
local HEARTH = {
  [6948] = {
    name = "Hearthstone",
    link = LINK,
    quality = 1,
    itemLevel = 1,
    minLevel = 1,
    type = "Miscellaneous",
    subType = "Junk",
    stackCount = 1,
    equipLoc = "",
    icon = 134414,
    classID = 15,
    subClassID = 0,
    count = 3,
  },
}
local INSTANT = { 6948, "Miscellaneous", "Junk", "", 134414, 15, 0 }

local function test_item_info_tuple_and_unknown_item() -- (G13)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      w:setMock({ items = HEARTH })
      A.same({ _G.C_Item.GetItemInfo(6948) }, { "Hearthstone", LINK, 1, 1, 1, "Miscellaneous", "Junk", 1, "", 134414, nil, 15, 0 }, flavor)
      A.same({ _G.C_Item.GetItemInfo("item:6948") }, { _G.C_Item.GetItemInfo(6948) }, flavor)
      A.same({ _G.C_Item.GetItemInfo(1) }, {}, flavor)
      A.eq(w.unscripted["C_Item.GetItemInfo"], 1, flavor)
    end)
  end
end

local function test_item_names_absent_on_every_flavor() -- (G1)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      for _, name in ipairs({ "GetItemInfo", "GetItemInfoInstant", "GetItemCount", "GetItemIcon" }) do
        A.eq(rawget(_G, name), nil, flavor .. " " .. name)
      end
    end)
  end
end

local function test_item_info_instant_count_and_icon() -- (G13)
  G.withGame("retail", function(w)
    w:setMock({ items = HEARTH })
    A.same({ _G.C_Item.GetItemInfoInstant(6948) }, INSTANT)
    A.same({ _G.C_Item.GetItemCount(6948), _G.C_Item.GetItemCount(1), _G.C_Item.GetItemIconByID(6948) }, { 3, 0, 134414 })
    A.same({ _G.C_Item.GetItemInfoInstant("Hearthstone") }, INSTANT)
    A.same({ _G.C_Item.GetItemInfoInstant(1) }, {})
  end)
end

local function test_default_link_names_the_item_assumed() -- (G13)
  G.withGame("vanilla", function(w)
    w:setMock({ items = { [6948] = { name = "Hearthstone", quality = 1 }, [25] = { name = "Worn Shortsword", quality = 0 } } })
    A.eq(select(2, _G.C_Item.GetItemInfo(6948)), LINK)
    A.eq(select(2, _G.C_Item.GetItemInfo(25)), "|cff9d9d9d|Hitem:25::::::::::::|h[Worn Shortsword]|h|r")
  end)
end

local function test_money_and_specialization() -- (G13)
  G.withGame("retail", function(w)
    A.same({ _G.GetMoney(), _G.C_SpecializationInfo.GetSpecialization() }, { 0 })
    w:setMock({
      money = 12345,
      spec = 2,
      specs = { [2] = { id = 63, name = "Fire", description = "d", icon = 1, role = "DAMAGER", primaryStat = 4 } },
    })
    A.same({ _G.GetMoney(), _G.C_SpecializationInfo.GetSpecialization() }, { 12345, 2 })
    A.same({ _G.C_SpecializationInfo.GetSpecializationInfo(2) }, { 63, "Fire", "d", 1, "DAMAGER", 4 })
    A.same({ _G.GetSpecialization(), _G.GetSpecializationInfo(2) }, { 2, 63, "Fire", "d", 1, "DAMAGER", 4 })
    A.same({ _G.C_SpecializationInfo.GetSpecializationInfo(9) }, {})
    A.eq(w.unscripted["C_SpecializationInfo.GetSpecializationInfo"], 1)
    w:setMock({ spec = false })
    A.same({ _G.C_SpecializationInfo.GetSpecialization() }, {})
  end)
end

local function test_num_specializations_counts_the_spec_records_assumed() -- (G13) SpellBookCategory:198 adds it to an index
  G.withGame("retail", function(w)
    A.eq(_G.GetNumSpecializations(false, false), 0)
    w:setMock({ specs = { { id = 71, name = "Arms" }, { id = 72, name = "Fury" }, { id = 73, name = "Protection" } } })
    A.eq(_G.GetNumSpecializations(false, false), 3)
  end)
end

local function test_specialization_fallbacks_only_on_retail_and_forever() -- (G1)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      local expected = flavor == "retail" or flavor == "forever"
      A.eq(type(rawget(_G, "GetSpecialization")) == "function", expected, flavor)
      A.eq(type(rawget(_G, "GetSpecializationInfo")) == "function", expected, flavor)
      A.eq(_G.GetMoney(), 0, flavor)
    end)
  end
end

return function()
  test_item_info_tuple_and_unknown_item()
  test_item_names_absent_on_every_flavor()
  test_item_info_instant_count_and_icon()
  test_default_link_names_the_item_assumed()
  test_money_and_specialization()
  test_num_specializations_counts_the_spec_records_assumed()
  test_specialization_fallbacks_only_on_retail_and_forever()
end

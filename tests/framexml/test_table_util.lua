-- Table and math helpers (framexml/fakes/table_util.lua). Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_copy_table_deep_copies_nested_tables() -- W71
  withFrameXML("retail", function()
    local orig = { a = { b = 1 }, c = 2 }
    local copy = _G.CopyTable(orig)
    A.eq(copy ~= orig, true)
    A.eq(copy.a ~= orig.a, true)
    A.same(copy, { a = { b = 1 }, c = 2 })
  end)
end

local function test_copy_table_shallow_shares_the_nested_tables() -- W71
  withFrameXML("retail", function()
    local orig = { a = { b = 1 } }
    local copy = _G.CopyTable(orig, true)
    A.eq(copy ~= orig, true)
    A.eq(copy.a, orig.a)
  end)
end

-- The client's copy starts from a plain table and sets no metatable.
local function test_copy_table_drops_the_metatable() -- W71
  withFrameXML("retail", function()
    local orig = setmetatable({ a = 1 }, { __index = { inherited = true } })
    local copy = _G.CopyTable(orig)
    A.eq(getmetatable(copy), nil)
    A.eq(copy.inherited, nil)
  end)
end

-- A global tCount is not defined in 12.x (only a local at securetypes.lua:15); the counting alias is CountTable.
local function test_count_table_counts_every_key_and_tcount_stays_absent() -- W71
  withFrameXML("retail", function()
    A.eq(_G.CountTable({ 1, 2, x = 3 }), 3)
    A.eq(_G.tCount, nil)
  end)
end

local function test_t_delete_item_removes_every_match_assumed() -- W71
  withFrameXML("retail", function()
    local list = { 1, 2, 1 }
    A.eq(_G.tDeleteItem(list, 1), 2)
    A.same(list, { 2 })
    A.eq(_G.tDeleteItem(list, 9), 0)
  end)
end

local function test_lerp_saturate_and_percentage_between() -- W71
  withFrameXML("retail", function()
    A.eq(_G.Lerp(0, 10, 0.25), 2.5)
    A.eq(_G.Saturate(2), 1)
    A.eq(_G.Saturate(-1), 0)
    A.eq(_G.Saturate(0.5), 0.5)
    A.eq(_G.PercentageBetween(5, 0, 10), 0.5)
  end)
end

local function test_percentage_between_is_zero_for_an_empty_range() -- W71
  withFrameXML("retail", function()
    A.eq(_G.PercentageBetween(5, 3, 3), 0)
  end)
end

local function test_nop_returns_nothing() -- W71
  withFrameXML("retail", function()
    A.eq(select("#", _G.nop(1, 2)), 0)
  end)
end

-- source: blizzard_sharedxmlbase/tableutil.lua:19 (extract retail 70575): TableIsEmpty is table.isempty, which a Blizzard addon
-- (UIParentPanelManager.lua:180) calls; the tbc extract has neither. That it is true only without any key is assumed.
local function test_table_isempty_exists_on_retail_and_forever_only_assumed()
  withFrameXML("retail", function()
    A.same({ _G.table.isempty({}), _G.table.isempty({ a = 1 }), _G.table.isempty({ 1 }) }, { true, false, false })
  end)
  withFrameXML("tbc", function()
    A.eq(_G.table.isempty, nil)
  end)
end

return function()
  test_table_isempty_exists_on_retail_and_forever_only_assumed()
  test_copy_table_deep_copies_nested_tables()
  test_copy_table_shallow_shares_the_nested_tables()
  test_copy_table_drops_the_metatable()
  test_count_table_counts_every_key_and_tcount_stays_absent()
  test_t_delete_item_removes_every_match_assumed()
  test_lerp_saturate_and_percentage_between()
  test_percentage_between_is_zero_for_an_empty_range()
  test_nop_returns_nothing()
end

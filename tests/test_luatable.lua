-- The engine's table.* extensions (luatable.lua): documented by LuaTableExtensions on retail 70575 and forever; rows BU20, W71.
local A = require("assert")
local H = require("tests.helpers.world")

local withWorld = H.withWorld

local DOCUMENTED = {
  "contains",
  "count",
  "create",
  "indexof",
  "freeze",
  "keys",
  "getcountinfo",
  "values",
  "isempty",
  "isfrozen",
  "removeunordered",
  "removevalue",
}
-- The names every flavor's Ketho LuaAPI list carries, so the older flavors have these too.
local EVERYWHERE = { "count", "create", "freeze", "isfrozen" }

local function sorted(list)
  table.sort(list)
  return list
end

local function test_retail_and_forever_define_every_documented_function() -- BU20
  for _, flavor in ipairs({ "retail", "forever" }) do
    withWorld(flavor, function(w)
      for _, name in ipairs(DOCUMENTED) do
        A.eq(type(_G.table[name]), "function", flavor .. " table." .. name)
        A.eq(w.unscripted["table." .. name], nil)
      end
    end)
  end
end

local function test_the_older_flavors_keep_only_the_names_their_list_carries() -- BU20
  for _, flavor in ipairs({ "tbc", "mists", "vanilla" }) do
    withWorld(flavor, function()
      A.eq(_G.table.contains, nil, flavor)
      A.eq(_G.table.keys, nil, flavor)
      A.eq(_G.table.isempty, nil, flavor)
      for _, name in ipairs(EVERYWHERE) do
        A.eq(type(_G.table[name]), "function", flavor .. " table." .. name)
      end
    end)
  end
end

-- Blizzard's TableUtil assigns tContains = _G.table.contains; a nil there is what broke FloatingChatFrame and the Minimap.
local function test_contains_answers_by_value_for_any_key() -- BU20
  withWorld("retail", function()
    local t = { 1, a = "x" }
    A.same({ _G.table.contains(t, 1), _G.table.contains(t, "x"), _G.table.contains(t, "y"), _G.table.contains(t, nil) }, { true, true, false, false })
  end)
end

local function test_count_counts_every_key_and_create_gives_an_empty_table() -- W71
  withWorld("tbc", function()
    A.eq(_G.table.count({ 1, 2, x = 3 }), 3)
    A.same(_G.table.create(4, 2), {})
  end)
end

local function test_indexof_stops_at_the_first_nil() -- BU20
  withWorld("retail", function()
    A.eq(_G.table.indexof({ "a", "b", "b" }, "b"), 2)
    A.eq(_G.table.indexof({ "a", nil, "b" }, "b"), nil)
    A.eq(_G.table.indexof({}, "a"), nil)
  end)
end

local function test_keys_and_values_return_arrays_of_every_entry() -- BU20
  withWorld("retail", function()
    local t = { 10, 20, x = 30 }
    local keys = _G.table.keys(t)
    A.eq(#keys, 3)
    A.same(sorted({ tostring(keys[1]), tostring(keys[2]), tostring(keys[3]) }), { "1", "2", "x" })
    A.same(sorted(_G.table.values(t)), { 10, 20, 30 })
  end)
end

local function test_getcountinfo_reports_entries_and_positive_integer_keys() -- BU20
  withWorld("forever", function()
    A.same({ _G.table.getcountinfo({}) }, { 0, 0, 0 })
    A.same({ _G.table.getcountinfo({ "a", "b", x = 1, [0] = 2, [-3] = 3, [7] = 4, [1.5] = 5 }) }, { 7, 3, 7 })
  end)
end

local function test_isempty_is_true_without_any_key() -- BU13
  withWorld("retail", function()
    A.same({ _G.table.isempty({}), _G.table.isempty({ a = 1 }), _G.table.isempty({ 1 }) }, { true, false, false })
  end)
end

local function test_freeze_returns_the_table_and_isfrozen_reads_the_mark_assumed() -- BU20
  withWorld("retail", function()
    local t = {}
    A.eq(_G.table.isfrozen(t), false)
    A.eq(_G.table.freeze(t), t)
    A.eq(_G.table.isfrozen(t), true)
    A.eq(_G.table.isfrozen({}), false)
  end)
end

local function test_removeunordered_swaps_the_last_value_in() -- BU20
  withWorld("retail", function()
    local t = { "a", "b", "c", "d" }
    A.eq(_G.table.removeunordered(t, 2), "b")
    A.same(t, { "a", "d", "c" })
    A.eq(_G.table.removeunordered(t), "c")
    A.same(t, { "a", "d" })
    A.eq(_G.table.removeunordered(t, 5), nil)
    A.eq(_G.table.removeunordered(t, 0), nil)
    A.eq(_G.table.removeunordered({}), nil)
    A.same(t, { "a", "d" })
    A.eq(_G.table.removeunordered(t, 2), "d")
    A.same(t, { "a" })
  end)
end

local function test_removevalue_removes_every_match_and_counts_them() -- W71
  withWorld("retail", function()
    local t = { 1, 2, 1, 3, 1 }
    A.eq(_G.table.removevalue(t, 1), 3)
    A.same(t, { 2, 3 })
    A.eq(_G.table.removevalue(t, 9), 0)
  end)
end

return function()
  test_retail_and_forever_define_every_documented_function()
  test_the_older_flavors_keep_only_the_names_their_list_carries()
  test_contains_answers_by_value_for_any_key()
  test_count_counts_every_key_and_create_gives_an_empty_table()
  test_indexof_stops_at_the_first_nil()
  test_keys_and_values_return_arrays_of_every_entry()
  test_getcountinfo_reports_entries_and_positive_integer_keys()
  test_isempty_is_true_without_any_key()
  test_freeze_returns_the_table_and_isfrozen_reads_the_mark_assumed()
  test_removeunordered_swaps_the_last_value_in()
  test_removevalue_removes_every_match_and_counts_them()
end

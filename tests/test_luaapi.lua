-- Ketho LuaAPI names installed per flavor: aliases, degree trig, string/table extensions, bit and Forever helpers.
local A = require("assert")
local H = require("tests.helpers.world")

local withWorld, lookup = H.withWorld, H.lookup

local function test_bit_band_on_retail()
  withWorld("retail", function()
    A.eq(_G.bit.band(6, 3), 2)
  end)
end

local function test_bit_ops_work_on_32_bit_ints()
  withWorld("vanilla", function()
    local bit = _G.bit
    A.eq(bit.bor(1, 2, 4), 7)
    A.eq(bit.bxor(5, 3), 6)
    A.eq(bit.bnot(0), 0xFFFFFFFF)
    A.eq(bit.lshift(0x80000000, 1), 0)
    A.eq(bit.rshift(8, 2), 2)
    A.eq(bit.arshift(0x80000000, 31), 0xFFFFFFFF)
    A.eq(bit.arshift(8, 2), 2)
  end)
end

local function test_string_and_table_extensions_on_retail()
  withWorld("retail", function()
    A.eq(lookup("string.trim")("  a "), "a")
    A.same({ lookup("string.split")(",", "a,b") }, { "a", "b" })
    A.eq(type(rawget(table, "wipe")), "function")
  end)
end

local function test_global_aliases_match_the_standard_library()
  withWorld("mists", function()
    A.eq(_G.sort, table.sort)
    A.eq(_G.gsub, string.gsub)
    A.eq(_G.strrep, string.rep)
    A.eq(_G.random, math.random)
    A.eq(_G.mod, math.fmod)
    A.eq(_G.getn({ 1, 2 }), 2)
  end)
end

local function test_global_trig_works_in_degrees()
  withWorld("tbc", function()
    A.eq(_G.sin(90), 1)
    A.eq(_G.deg(math.pi), 180)
    A.eq(_G.atan2(1, 0), 90)
  end)
end

local function test_forever_helpers_installed_only_on_forever()
  withWorld("forever", function()
    A.eq(_G.Round(2.5), 3)
    A.eq(_G.Clamp(5, 0, 3), 3)
    A.eq(_G.tIndexOf({ "a", "b" }, "b"), 2)
  end)
  withWorld("retail", function()
    A.eq(rawget(_G, "Round"), nil)
  end)
end

local function test_name_without_implementation_is_an_unscripted_stub()
  withWorld("retail", function(w)
    A.eq(lookup("table.freeze")({}), nil)
    A.eq(w.unscripted["table.freeze"], 1)
  end)
end

local function test_destroy_removes_library_installs()
  withWorld("retail", function() end)
  A.eq(rawget(string, "split"), nil)
  A.eq(rawget(table, "wipe"), nil)
  A.eq(rawget(_G, "sort"), nil)
end

return function()
  test_bit_band_on_retail()
  test_bit_ops_work_on_32_bit_ints()
  test_string_and_table_extensions_on_retail()
  test_global_aliases_match_the_standard_library()
  test_global_trig_works_in_degrees()
  test_forever_helpers_installed_only_on_forever()
  test_name_without_implementation_is_an_unscripted_stub()
  test_destroy_removes_library_installs()
end

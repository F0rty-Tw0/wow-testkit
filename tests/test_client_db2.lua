-- Client.db2: a DB2 table the extract exported, loaded once per extract; a chunked table (db2/<name>/<id // 10000>.lua)
-- loads one chunk at a time, on the first lookup of an id in it.
local A = require("assert")
local Client = require("client")
local H = require("tests.helpers.client")
local Tmp = require("tests.helpers.tmp")

local function test_db2_returns_the_exported_table_once_per_extract()
  local ex = H.extract(Tmp.dir("db2"), "retail", "1", { ["db2/spellname.lua"] = 'return { [133] = { Name_lang = "Fireball" } }' })
  A.eq(Client.db2(ex, "SpellName")[133].Name_lang, "Fireball") -- the name in any case
  A.eq(Client.db2(ex, "spellname"), Client.db2(ex, "SpellName")) -- one load, one table
end

local function chunked(files)
  return H.extract(Tmp.dir("db2chunk"), "retail", "1", files)
end

local function test_db2_chunks_split_at_ten_thousand_ids()
  local ex = chunked({
    ["db2/spellname/0.lua"] = 'return { [133] = { Name_lang = "Fireball" }, [9999] = { Name_lang = "Last" } }',
    ["db2/spellname/1.lua"] = 'return { [10000] = { Name_lang = "First" } }',
  })
  local names = Client.db2(ex, "SpellName")
  A.eq(names[9999].Name_lang, "Last")
  A.eq(names[10000].Name_lang, "First")
  A.eq(names[133].Name_lang, "Fireball")
  A.eq(Client.db2(ex, "spellname"), names) -- one proxy per extract
end

local function test_db2_chunk_is_loaded_on_the_first_lookup_in_it()
  local ex = chunked({
    ["db2/item/0.lua"] = "return { [6948] = { ClassID = 15 } }",
    ["db2/item/1.lua"] = "return {", -- a broken chunk the first lookup never touches
  })
  local items = Client.db2(ex, "Item")
  A.eq(items[6948].ClassID, 15)
  A.eq(items[10001], nil) -- the broken chunk: nil, no error
end

local function test_db2_missing_chunk_or_odd_key_is_nil()
  local ex = chunked({ ["db2/item/0.lua"] = "return { [1] = {} }" })
  local items = Client.db2(ex, "Item")
  A.eq(items[250000], nil)
  A.eq(items[1.5], nil)
  A.eq(items.name, nil)
  A.eq(items[-3], nil)
end

local function test_db2_is_nil_for_an_absent_table_or_extract()
  local ex = H.extract(Tmp.dir("db2none"), "retail", "1", {})
  A.eq(Client.db2(ex, "SpellName"), nil)
  A.eq(Client.db2(nil, "SpellName"), nil) -- no extract: nil, no error
end

local function test_db2_is_nil_for_a_file_that_does_not_load()
  local ex = H.extract(Tmp.dir("db2bad"), "retail", "1", { ["db2/item.lua"] = "return {" })
  A.eq(Client.db2(ex, "Item"), nil)
end

test_db2_returns_the_exported_table_once_per_extract()
test_db2_is_nil_for_an_absent_table_or_extract()
test_db2_is_nil_for_a_file_that_does_not_load()
test_db2_chunks_split_at_ten_thousand_ids()
test_db2_chunk_is_loaded_on_the_first_lookup_in_it()
test_db2_missing_chunk_or_odd_key_is_nil()

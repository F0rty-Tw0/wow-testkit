-- Client.db2: a DB2 table the extract exported, loaded once per extract.
local A = require("assert")
local Client = require("client")
local H = require("tests.helpers.client")
local Tmp = require("tests.helpers.tmp")

local function test_db2_returns_the_exported_table_once_per_extract()
  local ex = H.extract(Tmp.dir("db2"), "retail", "1", { ["db2/spellname.lua"] = 'return { [133] = { Name_lang = "Fireball" } }' })
  A.eq(Client.db2(ex, "SpellName")[133].Name_lang, "Fireball") -- the name in any case
  A.eq(Client.db2(ex, "spellname"), Client.db2(ex, "SpellName")) -- one load, one table
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

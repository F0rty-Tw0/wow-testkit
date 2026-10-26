-- Wtf.read: SavedVariables files of a WTF account and character folder, run in an empty environment and cut down to the
-- names the addon's TOC lists for each file.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Wtf = require("session_wtf")
local fs = require("fs")

local INFO = { savedVariables = { "WtfDemoDB" }, savedVariablesPerCharacter = { "WtfDemoCharDB" } }

-- A fresh dir with acc.lua and char.lua, each written when given; returns { account?, character? } paths of those.
local function files(account, character)
  local dir = Tmp.dir("wtf")
  local paths = {}
  if account then
    paths.account = dir .. "/acc.lua"
    fs.writeFile(paths.account, account)
  end
  if character then
    paths.character = dir .. "/char.lua"
    fs.writeFile(paths.character, character)
  end
  return paths
end

local function test_reads_account_and_character_files()
  local saved, warnings = Wtf.read(INFO, files("WtfDemoDB = { n = 1 } Other = 2", "WtfDemoCharDB = { c = true }"))
  A.same(saved, { WtfDemoDB = { n = 1 }, WtfDemoCharDB = { c = true } })
  A.eq(#warnings, 0)
end

local function test_keeps_only_toc_listed_names_per_file()
  A.same(Wtf.read(INFO, files("WtfDemoCharDB = 5", "WtfDemoDB = 9")), {})
  A.same(Wtf.read(INFO, files("WtfDemoCharDB = 5")), {})
  A.same(Wtf.read(INFO, { character = files(nil, "WtfDemoDB = 9").character }), {})
end

local function test_syntax_error_is_skipped_with_a_warning()
  local saved, warnings = Wtf.read(INFO, files("WtfDemoDB = {", "WtfDemoCharDB = { c = true }"))
  A.eq(saved.WtfDemoDB, nil)
  A.same(saved.WtfDemoCharDB, { c = true })
  A.contains(warnings[1], "acc.lua")
end

local function test_bytecode_is_refused()
  local saved, warnings = Wtf.read(INFO, files(string.dump(function() end)))
  A.contains(warnings[1], "bytecode refused")
  A.same(saved, {})
end

local function test_file_cannot_reach_globals_or_os()
  local _, warnings = Wtf.read(INFO, files("_G.x = 1"))
  A.eq(#warnings, 1)
  A.eq(rawget(_G, "x"), nil)
  _, warnings = Wtf.read(INFO, files("os.exit(3)"))
  A.eq(#warnings, 1)
end

local function test_missing_file_warns()
  local _, warnings = Wtf.read(INFO, { account = Tmp.dir("wtf") .. "/none.lua" })
  A.eq(warnings[1]:sub(1, #"wtf: cannot read"), "wtf: cannot read")
end

return function()
  test_reads_account_and_character_files()
  test_keeps_only_toc_listed_names_per_file()
  test_syntax_error_is_skipped_with_a_warning()
  test_bytecode_is_refused()
  test_file_cannot_reach_globals_or_os()
  test_missing_file_warns()
end

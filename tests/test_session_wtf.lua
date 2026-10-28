-- Wtf.read: SavedVariables files of a WTF account and character folder, run in an empty environment and cut down to the
-- names the addon's TOC lists for each file. Wtf.open and Wtf.apply: a whole WTF folder read and put into a world.
local A = require("assert")
local H = require("tests.helpers.session")
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

-- Wtf.open: a whole WTF folder (Config.wtf, Account/<NAME>/..., <Realm>/<Character>/...) read without writing.

-- Header: version 1, 2 account settings (5 7). Layout "Cozy 25 Raid" (a 12-byte name, three systems: the last with a
-- second anchor and an empty relativeTo), then "Solo" (4 bytes, no systems).
local COZY_SYSTEMS = "0 0 1 7 7 UIParent 0.0 45.0 -1 ##$$ 11 -1 0 5 5 UIParent -5.0 -77.0 -1 #$ 12 -1 0 0 0  1.5 -2.0 8 8 UIParent 3.0 4.0 %#"
local EDIT_MODE = "1 2 5 7 12 Cozy 25 Raid 3 " .. COZY_SYSTEMS .. " 4 Solo 0\0"

local TREE = {
  ["Config.wtf"] = 'SET gxResolution "1920x1080"\nSET cameraDistanceMaxZoomFactor "1.9"\n',
  ["Account/SavedVariables/Blizzard_SavedSets.lua"] = "x = 1\n",
  ["Account/ACC#1/config-cache.wtf"] = 'SET cameraDistanceMaxZoomFactor "2.6"\nSET Sound_MasterVolume "0.2"\n',
  ["Account/ACC#1/bindings-cache.wtf"] = "bind K MINI_TOGGLE\nbind A STRAFELEFT\n",
  ["Account/ACC#1/edit-mode-cache-account.txt"] = EDIT_MODE,
  ["Account/ACC#1/SavedVariables/MiniAddon.lua"] = "MiniDB = { runs = 7 }\n",
  ["Account/ACC#1/SavedVariables/MiniAddon.lua.bak"] = "MiniDB = { runs = 1 }\n",
  ["Account/ACC#1/Realm One/Cozy/config-cache.wtf"] = 'SET Sound_MasterVolume "0.5"\n',
  ["Account/ACC#1/Realm One/Cozy/edit-mode-cache-character.txt"] = "1 4 4 4 4 4\0",
  ["Account/ACC#1/Realm One/Cozy/SavedVariables/miniaddon.lua"] = "MiniChar = { x = 1 }\n",
}

-- A fresh WTF folder holding TREE plus extra (path -> text); returns its path.
local function tree(extra)
  local dir = Tmp.dir("wtfdir")
  for _, layer in ipairs({ TREE, extra or {} }) do
    for path, text in pairs(layer) do
      fs.mkdirp((dir .. "/" .. path):match("^(.*)/[^/]*$"))
      fs.writeFile(dir .. "/" .. path, text)
    end
  end
  return dir
end

local COZY = { realm = "Realm One", character = "Cozy" }

local function test_cvars_merge_config_then_account_then_character()
  local wtf = Wtf.open(tree(), COZY)
  A.eq(wtf.cvars.cameradistancemaxzoomfactor, "2.6")
  A.eq(wtf.cvars.sound_mastervolume, "0.5")
  A.eq(wtf.cvars.gxresolution, "1920x1080")
  A.eq(Wtf.open(tree()).cvars.sound_mastervolume, "0.2", "without a character the account file wins")
end

local function test_config_lines_other_than_set_are_ignored()
  local cvars = Wtf.parseConfig('SET A "1"\r\n# note\nSET Empty ""\nset b "2"\nSET C unquoted\n')
  A.same(cvars, { a = "1", empty = "" })
end

local function test_one_account_is_picked_and_several_need_a_name()
  local dir = tree()
  A.same(Wtf.accounts(dir), { "ACC#1" })
  A.eq(Wtf.open(dir).account, "ACC#1")
  fs.mkdirp(dir .. "/Account/ACC#2")
  A.same(Wtf.accounts(dir), { "ACC#1", "ACC#2" })
  local none, err = Wtf.open(dir)
  A.eq(none, nil)
  A.eq(err, "several accounts: ACC#1, ACC#2; pass --wtf-account")
  A.eq(Wtf.open(dir, { account = "acc#2" }).account, "ACC#2")
end

local function test_a_missing_folder_account_or_character_is_an_error()
  local dir = tree()
  A.same({ Wtf.open(dir .. "/none") }, { nil, "no WTF folder at " .. dir .. "/none" })
  A.same({ Wtf.open(dir, { account = "ACC#9" }) }, { nil, "no account ACC#9 in " .. dir .. "/Account" })
  A.same({ Wtf.open(dir, { realm = "Realm One", character = "Nobody" }) }, { nil, "no character Realm One/Nobody in account ACC#1" })
end

local function test_files_for_finds_the_addon_files_ignoring_case()
  local dir = tree()
  local found = Wtf.open(dir, COZY).filesFor("MiniAddon")
  A.same(found, {
    account = dir .. "/Account/ACC#1/SavedVariables/MiniAddon.lua",
    character = dir .. "/Account/ACC#1/Realm One/Cozy/SavedVariables/miniaddon.lua",
  })
  A.same(Wtf.open(dir).filesFor("miniaddon"), { account = found.account })
  A.same(Wtf.open(dir, COZY).filesFor("Other"), {})
  local saved = Wtf.read({ savedVariables = { "MiniDB" }, savedVariablesPerCharacter = { "MiniChar" } }, found)
  A.same(saved, { MiniDB = { runs = 7 }, MiniChar = { x = 1 } }, "the .bak copy is never read")
end

local function test_edit_mode_cache_parses_layouts_and_systems_assumed()
  local layouts = Wtf.open(tree()).editMode
  local anchor1 = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 45 }
  local anchor2 = { point = "RIGHT", relativeTo = "UIParent", relativePoint = "RIGHT", offsetX = -5, offsetY = -77 }
  local system1 = { system = 0, systemIndex = 0, isInDefaultPosition = true, anchorInfo = anchor1, settings = {}, settingsRaw = "##$$" }
  local system2 = { system = 11, isInDefaultPosition = false, anchorInfo = anchor2, settings = {}, settingsRaw = "#$" }
  local anchor3 = { point = "TOPLEFT", relativeTo = "", relativePoint = "TOPLEFT", offsetX = 1.5, offsetY = -2 }
  local second = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = 3, offsetY = 4 }
  local system3 = { system = 12, isInDefaultPosition = false, anchorInfo = anchor3, anchorInfo2 = second, settings = {}, settingsRaw = "%#" }
  A.same(layouts, {
    { layoutType = 1, layoutName = "Cozy 25 Raid", systems = { system1, system2, system3 } },
    { layoutType = 1, layoutName = "Solo", systems = {} },
  })
end

local function test_unparsable_edit_mode_cache_is_a_warning_assumed()
  local badSecondAnchor = "1 2 5 7 4 Raid 1 0 0 1 7 7 UIParent 0.0 45.0 3 ##$$"
  local badNameLength = "1 2 5 7 3 Raid 0"
  for _, text in ipairs({ "garbage", "1 9 0", badSecondAnchor, badNameLength, "1 0 4 Solo 0 " }) do
    local wtf = Wtf.open(tree({ ["Account/ACC#1/edit-mode-cache-account.txt"] = text }), COZY)
    A.eq(wtf.editMode, nil, text)
    A.eq(#wtf.warnings, 1, text)
    A.contains(wtf.warnings[1], "edit-mode-cache-account.txt")
    A.eq(wtf.cvars.sound_mastervolume, "0.5", "the rest is still read")
  end
  local empty = Wtf.open(tree({ ["Account/ACC#1/edit-mode-cache-account.txt"] = "1 2 0 100\0" }))
  A.same({ empty.editMode, #empty.warnings }, { nil, 0 })
end

local function test_active_layout_comes_from_the_character_file_assumed()
  A.eq(Wtf.open(tree(), COZY).activeLayout, 4)
  A.eq(Wtf.open(tree()).activeLayout, nil, "no character, no active layout")
  local path = "Account/ACC#1/Realm One/Cozy/edit-mode-cache-character.txt"
  for _, text in ipairs({ "1 -1 -1 -1 -1 -1\0", "1 5 5 5 5 5\0", "1 0\0", "x" }) do
    A.eq(Wtf.open(tree({ [path] = text }), COZY).activeLayout, nil, text)
  end
end

local function test_apply_sets_cvars_bindings_and_layouts_assumed()
  local wtf = Wtf.open(tree(), COZY)
  H.withSession(nil, function(sess)
    Wtf.apply(sess.w, wtf)
    A.eq(_G.GetCVar("Sound_MasterVolume"), "0.5")
    A.eq(_G.GetBindingAction("K"), "MINI_TOGGLE")
    local info = _G.C_EditMode.GetLayouts()
    A.same({ #info.layouts, info.layouts[1].layoutName, info.activeLayout }, { 2, "Cozy 25 Raid", 4 })
  end)
  local noCharacter = Wtf.open(tree())
  H.withSession(nil, function(sess)
    Wtf.apply(sess.w, noCharacter)
    A.eq(_G.C_EditMode.GetLayouts().activeLayout, 3, "the first saved layout")
  end)
end

-- Every file under dir (path -> contents), recursively.
local function contents(dir, out)
  out = out or {}
  for _, name in ipairs(fs.list(dir)) do
    local path = dir .. "/" .. name
    if fs.isdir(path) then
      contents(path, out)
    else
      out[path] = fs.readFile(path)
    end
  end
  return out
end

-- Runs fn with fs.readFile, fs.list and fs.isdir recording each path they get; returns the paths.
local function recordingPaths(fn)
  local seen, saved = {}, {}
  for _, name in ipairs({ "readFile", "list", "isdir" }) do
    local original = fs[name]
    saved[name] = original
    fs[name] = function(path, ...)
      seen[#seen + 1] = path
      return original(path, ...)
    end
  end
  local ok, err = pcall(fn)
  for name, original in pairs(saved) do
    fs[name] = original
  end
  assert(ok, err)
  return seen
end

local function test_open_never_writes_and_reads_only_under_the_wtf_dir()
  local dir = tree()
  local before = contents(dir)
  local wtf
  local paths = recordingPaths(function()
    wtf = Wtf.open(dir, COZY)
    Wtf.read({ savedVariables = { "MiniDB" }, savedVariablesPerCharacter = { "MiniChar" } }, wtf.filesFor("MiniAddon"))
  end)
  H.withSession(nil, function(sess)
    Wtf.apply(sess.w, wtf)
  end)
  A.same(contents(dir), before)
  local outside = {}
  for _, path in ipairs(paths) do
    local under = path == dir or path:sub(1, #dir + 1) == dir .. "/"
    outside[#outside + 1] = not under and path or nil
  end
  A.same(outside, {})
  A.truthy(#paths > 10, "the reads were recorded")
end

return function()
  test_reads_account_and_character_files()
  test_keeps_only_toc_listed_names_per_file()
  test_syntax_error_is_skipped_with_a_warning()
  test_bytecode_is_refused()
  test_file_cannot_reach_globals_or_os()
  test_missing_file_warns()
  test_cvars_merge_config_then_account_then_character()
  test_config_lines_other_than_set_are_ignored()
  test_one_account_is_picked_and_several_need_a_name()
  test_a_missing_folder_account_or_character_is_an_error()
  test_files_for_finds_the_addon_files_ignoring_case()
  test_edit_mode_cache_parses_layouts_and_systems_assumed()
  test_unparsable_edit_mode_cache_is_a_warning_assumed()
  test_active_layout_comes_from_the_character_file_assumed()
  test_apply_sets_cvars_bindings_and_layouts_assumed()
  test_open_never_writes_and_reads_only_under_the_wtf_dir()
end

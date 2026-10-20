-- TOC selection, parsing, declared-interface check and per-flavor file lists. Pure: also runs on the system Lua.
local A = require("assert")
local Flavors = require("tools.flavors")
local Toc = require("toc")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local SMOKE_DIR = TEST_DIR .. "/fixtures/smoke"

local function parseFixture(name)
  return Toc.parse(assert(fs.readFile(ADDONS_DIR .. "/" .. name .. "/" .. name .. ".toc")))
end

local function readerFor(name)
  return function(path)
    return fs.readFile(ADDONS_DIR .. "/" .. name .. "/" .. path)
  end
end

local function filesOn(name, flavor)
  return Toc.filesFor(parseFixture(name), flavor, readerFor(name))
end

local function test_parse_reads_meta_keys_as_written()
  local meta = parseFixture("Multi").meta
  A.eq(meta["Interface"], "120100")
  A.eq(meta["Interface-Vanilla"], "11509")
  A.eq(meta["Title"], "Multi")
end

local function test_parse_skips_comments_and_blank_lines()
  local parsed = Toc.parse("# comment\n\n## Title: T\r\nA.lua\r\n  \n#B.lua\n")
  A.same(parsed.files, { { path = "A.lua", directives = {} } })
end

local function test_parse_turns_backslashes_into_slashes()
  A.eq(Toc.parse("Core\\Init.lua\n").files[1].path, "Core/Init.lua")
end

local function test_parse_reads_trailing_directive_args_lowercased()
  local file = Toc.parse("Both.lua [AllowLoadGameType Vanilla, tbc  classic]\n").files[1]
  A.eq(file.path, "Both.lua")
  A.same(file.directives, { AllowLoadGameType = { vanilla = true, tbc = true, classic = true } })
end

local function test_parse_lists_saved_variables()
  local parsed = parseFixture("Multi")
  A.same(parsed.savedVariables, { "MultiDB", "MultiOtherDB" })
  A.same(parsed.savedVariablesPerCharacter, { "MultiCharDB" })
end

local function test_multi_loads_on_retail_vanilla_and_forever()
  local meta = parseFixture("Multi").meta
  A.eq(Toc.declared(meta, "retail"), "load")
  A.eq(Toc.declared(meta, "vanilla"), "load")
  A.eq(Toc.declared(meta, "forever"), "load")
end

local function test_interface_list_belongs_by_major_minor()
  local meta = parseFixture("WMStyle").meta
  A.eq(Toc.declared(meta, "retail"), "load")
  A.eq(Toc.declared(meta, "forever"), "load")
  A.eq(Toc.declared(meta, "vanilla"), "not-declared")
  A.eq(Toc.declared(meta, "tbc"), "not-declared")
end

local function test_lower_patch_is_outdated_higher_patch_is_ahead()
  local tbc = Flavors.get("tbc").tocVersion
  A.eq(Toc.declared({ ["Interface-TBC"] = tostring(tbc - 1) }, "tbc"), "outdated")
  A.eq(Toc.declared({ ["Interface-TBC"] = tostring(tbc + 1) }, "tbc"), "ahead")
end

local function test_missing_interface_is_not_declared()
  A.eq(Toc.declared({}, "retail"), "not-declared")
end

local function test_declared_outdated_within_version_line()
  A.eq(Toc.declared({ Interface = "120001" }, "retail"), "outdated")
end

local function test_declared_outdated_within_version_line_on_mists()
  A.eq(Toc.declared({ ["Interface-Mists"] = "50400" }, "mists"), "outdated")
end

local function test_declared_outdated_within_version_line_on_tbc()
  A.eq(Toc.declared({ ["Interface-TBC"] = "20400" }, "tbc"), "outdated")
end

local function test_declared_old_vanilla_value_not_outdated_on_vanilla()
  A.eq(Toc.declared({ ["Interface-Vanilla"] = "11404" }, "vanilla"), "not-declared")
end

local function test_declared_other_major_not_declared()
  A.eq(Toc.declared({ Interface = "50503" }, "retail"), "not-declared")
end

local function test_declared_same_major_higher_not_declared()
  A.eq(Toc.declared({ Interface = "120200" }, "retail"), "not-declared")
end

local function test_declared_vanilla_value_not_outdated_on_forever()
  A.eq(Toc.declared({ Interface = "11508" }, "forever"), "not-declared")
  A.eq(Toc.declared({ Interface = "11404" }, "forever"), "not-declared")
end

local function test_select_prefers_flavor_suffix_toc()
  A.eq(Toc.select(ADDONS_DIR .. "/Suffix", "Suffix", "vanilla"), ADDONS_DIR .. "/Suffix/Suffix_Vanilla.toc")
  A.eq(Toc.select(ADDONS_DIR .. "/Suffix", "Suffix", "retail"), ADDONS_DIR .. "/Suffix/Suffix.toc")
end

local function test_mainline_only_file_loads_on_retail_and_forever_not_vanilla()
  A.contains((filesOn("Multi", "retail")), "Only.lua")
  A.contains((filesOn("Multi", "forever")), "Only.lua")
  local vanilla = filesOn("Multi", "vanilla")
  for _, path in ipairs(vanilla) do
    A.truthy(path ~= "Only.lua", "Only.lua excluded on vanilla")
  end
end

local function test_game_type_list_matches_any_listed_type()
  A.contains((filesOn("Multi", "tbc")), "Both.lua")
  for _, path in ipairs((filesOn("Multi", "retail"))) do
    A.truthy(path ~= "Both.lua", "Both.lua excluded on retail")
  end
end

local function test_unknown_game_type_loads_everywhere_and_is_reported()
  for _, flavor in ipairs(Flavors.list) do
    local files, report = filesOn("Multi", flavor)
    A.contains(files, "Any.lua", flavor)
    A.contains(table.concat(report, "\n"), "foo", flavor)
  end
end

local function test_wrath_or_cata_only_file_loads_on_no_flavor_assumed()
  local parsed = Toc.parse("Wrath.lua [AllowLoadGameType wrath]\nCata.lua [AllowLoadGameType Cata]\n")
  for _, flavor in ipairs(Flavors.list) do
    local files, report = Toc.filesFor(parsed, flavor, function() end)
    A.same(files, {}, flavor)
    A.same(report, {}, flavor)
  end
end

local function test_xml_expands_to_its_scripts_in_place()
  A.same((filesOn("Multi", "retail")), { "A.lua", "Only.lua", "Any.lua", "X.lua" })
end

local function test_xml_include_expands_relative_to_its_directory()
  local xml = {
    ["UI/Main.xml"] = '<Ui><Include file="Sub\\Inner.xml"/><Script file="Main.lua"/></Ui>',
    ["UI/Sub/Inner.xml"] = '<?xml version="1.0"?><!-- note --><Ui><Script file="Inner.lua"/></Ui>',
  }
  local files, report = Toc.filesFor(Toc.parse("UI/Main.xml\n"), "retail", function(path)
    return xml[path]
  end)
  A.same(files, { "UI/Sub/Inner.lua", "UI/Main.lua" })
  A.same(report, {})
end

local function test_unsupported_xml_content_and_directives_are_reported()
  local xml = '<Ui><Frame name="F"><Scripts/></Frame><Script>print(1)</Script></Ui>'
  local parsed = Toc.parse("A.lua [AllowLoad Game]\nUi.xml\n")
  local files, report = Toc.filesFor(parsed, "retail", function()
    return xml
  end)
  A.same(files, { "A.lua" })
  local text = table.concat(report, "\n")
  A.contains(text, "AllowLoad")
  A.contains(text, "<Frame>")
  A.contains(text, "inline <Script>")
end

local function test_unreadable_xml_is_reported()
  local files, report = Toc.filesFor(Toc.parse("Missing.xml\n"), "retail", function()
    return nil
  end)
  A.same(files, {})
  A.contains(report[1], "Missing.xml")
end

local function test_addon_name_from_folder()
  A.eq(Toc.addonName(ADDONS_DIR .. "/Multi"), "Multi")
end

local function test_addon_name_ambiguous()
  local name, message = Toc.addonName(SMOKE_DIR .. "/NoName")
  A.eq(name, nil)
  A.contains(message, "found 2 TOC names")
end

return function()
  test_parse_reads_meta_keys_as_written()
  test_parse_skips_comments_and_blank_lines()
  test_parse_turns_backslashes_into_slashes()
  test_parse_reads_trailing_directive_args_lowercased()
  test_parse_lists_saved_variables()
  test_multi_loads_on_retail_vanilla_and_forever()
  test_interface_list_belongs_by_major_minor()
  test_lower_patch_is_outdated_higher_patch_is_ahead()
  test_missing_interface_is_not_declared()
  test_declared_outdated_within_version_line()
  test_declared_outdated_within_version_line_on_mists()
  test_declared_outdated_within_version_line_on_tbc()
  test_declared_old_vanilla_value_not_outdated_on_vanilla()
  test_declared_other_major_not_declared()
  test_declared_same_major_higher_not_declared()
  test_declared_vanilla_value_not_outdated_on_forever()
  test_select_prefers_flavor_suffix_toc()
  test_mainline_only_file_loads_on_retail_and_forever_not_vanilla()
  test_game_type_list_matches_any_listed_type()
  test_unknown_game_type_loads_everywhere_and_is_reported()
  test_wrath_or_cata_only_file_loads_on_no_flavor_assumed()
  test_xml_expands_to_its_scripts_in_place()
  test_xml_include_expands_relative_to_its_directory()
  test_unsupported_xml_content_and_directives_are_reported()
  test_unreadable_xml_is_reported()
  test_addon_name_from_folder()
  test_addon_name_ambiguous()
end

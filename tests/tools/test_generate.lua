local A = require("assert")
local Docs = require("tools.docs")
local Generate = require("tools.generate")
local GenerateIo = require("tools.generate_io")
local Serialize = require("serialize")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local DOCS_DIR = TEST_DIR .. "/../fixtures/docs"
local KETHO_DIR = TEST_DIR .. "/../fixtures/ketho"
local META = { flavor = "retail", branch = "live", version = "12.1.0.69933", mirrorCommit = "abc123" }

local entries = Docs.loadDir(DOCS_DIR)
local ketho = GenerateIo.loadKetho(KETHO_DIR)
local result = Generate.build(entries, ketho, META)
local manifest, globals, report = result.manifest, result.globals, result.report

local function test_argument_is_normalized_with_lua_type()
  A.same(manifest.functions.UnitName.args[1], { name = "unit", type = "UnitToken", lua = "string", nilable = false })
end

local function test_secret_when_flag_becomes_a_when_condition()
  A.eq(manifest.functions.UnitName.secret.when[1], "UnitNameIdentityRestricted")
  A.eq(manifest.functions.UnitName.secret.returns, "when")
end

local function test_secret_arguments_are_copied()
  A.eq(manifest.functions.UnitName.secret.args, "AllowedWhenTainted")
end

local function test_default_true_is_kept()
  A.eq(manifest.functions.UnitHealth.args[2].default, true)
end

local function test_default_false_is_kept()
  A.eq(manifest.functions.UnitIsOwnerOrControllerOfUnit.args[3].default, false)
end

local function test_absent_default_stays_absent()
  A.eq(manifest.functions.UnitHealth.args[1].default, nil)
end

local function test_function_level_secure_only_is_marked()
  A.eq(manifest.functions.UnitSetRole.secureOnly, true)
end

local function test_system_level_secure_only_is_inherited_under_namespaced_key()
  A.eq(manifest.functions["C_SecureSystem.DoSecureThing"].secureOnly, true)
end

local function test_unrestricted_function_omits_secure_only()
  A.eq(manifest.functions.UnitExists.secureOnly, nil)
end

local function test_secret_returns_true_is_always()
  A.eq(manifest.functions.UnitPosition.secret.returns, "always")
end

local function test_function_without_secret_flags_never_returns_secrets()
  A.eq(manifest.functions.UnitExists.secret.returns, "never")
end

local function test_may_return_nothing_is_kept()
  A.eq(manifest.functions.UnitPosition.mayReturnNothing, true)
  A.eq(manifest.functions.UnitExists.mayReturnNothing, nil)
end

local function test_never_secret_return_is_marked()
  A.eq(manifest.functions.UnitExists.returns[1].neverSecret, true)
end

local function test_widget_method_is_protected()
  A.eq(manifest.widgets.SimpleFrameAPI.methods.SetPoint.protected, true)
end

local function test_widget_method_const_secret_accessor_is_kept()
  A.eq(manifest.widgets.SimpleFrameAPI.methods.GetAnchorInfo.constSecretAccessor, true)
end

local function test_widget_methods_stay_out_of_functions()
  A.eq(manifest.functions.SetPoint, nil)
end

local function test_script_object_tables_stay_out_of_structs()
  A.eq(manifest.structs.SimpleFrameAnchorInfo, nil)
end

local function test_type_defined_only_in_script_object_maps_to_any_and_is_reported()
  A.eq(manifest.widgets.SimpleFrameAPI.methods.GetAnchorInfo.returns[1].lua, "any")
  A.eq(report.unknownTypes.SimpleFrameAnchorInfo, true)
end

local function test_event_is_keyed_by_literal_name()
  A.eq(manifest.events.UnitHealth, nil)
  A.same(manifest.events.UNIT_HEALTH.payload[1], { name = "unitTarget", type = "UnitTokenVariant", lua = "string", nilable = false })
end

local function test_secret_in_chat_messaging_lockdown_becomes_a_when_condition()
  A.same(manifest.events.UNIT_HEALTH.secretWhen, { "ChatMessagingLockdown" })
end

local function test_enum_fields_and_meta_are_collected()
  A.same(manifest.enums.UnitSex, { Male = 0, Female = 1 })
  A.same(manifest.enums.FooMeta, { NumValues = 2, MinValue = 1, MaxValue = 2 })
end

local function test_constants_are_resolved()
  A.eq(manifest.constants.X.W, 16)
  A.eq(manifest.constants.X.S, "XVV")
end

local function test_enum_typed_string_constant_becomes_the_enum_value()
  A.eq(manifest.constants.X.Q, 1)
end

local function test_struct_fields_map_enum_types_to_number()
  A.same(manifest.structs.UnitSexInfo.fields[1], { name = "sex", type = "UnitSex", lua = "number", nilable = false })
end

local function test_meta_fields_are_copied()
  A.eq(manifest.flavor, "retail")
  A.eq(manifest.branch, "live")
  A.eq(manifest.version, "12.1.0.69933")
  A.eq(manifest.mirrorCommit, "abc123")
end

local function test_files_group_parts_by_source_file()
  A.truthy(result.files.Unit.functions.UnitName, "Unit file holds UnitName")
  A.truthy(result.files.Enum.enums.Foo, "Enum file holds Foo")
  A.truthy(result.files.SimpleFrameAPI.widgets.SimpleFrameAPI, "widget file holds its widget")
end

local function test_file_that_produces_nothing_is_skipped()
  A.eq(result.files.UsesEnum, nil)
end

local function test_global_api_name_absent_from_docs_lands_in_globals_api()
  A.eq(globals.api.GetTime, true)
end

local function test_global_api_name_present_in_docs_stays_out_of_globals_api()
  A.eq(globals.api.UnitName, nil)
  A.eq(globals.api["C_SecureSystem.DoSecureThing"], nil)
end

local function test_lua_api_names_land_in_globals_lua()
  A.same(globals.lua, { abs = true, ["string.format"] = true })
end

local function test_globals_frames_exclude_load_on_demand()
  A.same(globals.frames, { UIParent = true, WorldFrame = true })
end

local function test_globals_framexml_exclude_load_on_demand()
  A.same(globals.framexml, { ToggleFrame = true, UIParent_OnLoad = true })
end

local function test_globals_events_flatten_every_system()
  A.same(globals.events, { PLAYER_LOGIN = true, UNIT_HEALTH = true, UNIT_NAME_UPDATE = true })
end

local function test_globals_widgets_is_the_ketho_table()
  A.same(globals.widgets, ketho.WidgetAPI)
end

local function test_returns_never_secret_is_carried()
  A.eq(manifest.functions.UnitIsPlayer.secret.returnsNeverSecret, true)
  A.eq(manifest.functions.UnitExists.secret.returnsNeverSecret, nil)
end

local function systemEntry(file, fn)
  return { file = file, doc = { Name = file, Type = "System", Functions = { fn } } }
end

local function test_duplicate_key_across_files_is_reported_and_last_file_wins()
  local dupEntries = {
    systemEntry("BDocumentation.lua", { Name = "Dup", Type = "Function", MayReturnNothing = true }),
    systemEntry("ADocumentation.lua", { Name = "Dup", Type = "Function" }),
  }
  local dup = Generate.build(dupEntries, ketho, META)
  A.same(dup.report.duplicates, { "functions:Dup A B" })
  A.eq(dup.manifest.functions.Dup.mayReturnNothing, true)
end

local function test_fixture_docs_have_no_duplicates()
  A.same(report.duplicates, {})
end

local function test_ignored_doc_fields_are_counted()
  local fn = {
    Name = "Aspected",
    Type = "Function",
    SecretReturnsForAspect = { 1 },
    SecretArgumentsAddAspect = { 2 },
    Arguments = { { Name = "list", Type = "table", InnerType = "number", Nilable = false } },
    Returns = { { Name = "color", Type = "colorRGB", Mixin = "ColorMixin", Nilable = false } },
  }
  local ignored = Generate.build({ systemEntry("ADocumentation.lua", fn) }, ketho, META).report.ignoredFields
  A.same(ignored, { SecretReturnsForAspect = 1, SecretArgumentsAddAspect = 1, InnerType = 1, Mixin = 1 })
end

local function test_build_twice_dumps_byte_identical()
  local again = Generate.build(Docs.loadDir(DOCS_DIR), GenerateIo.loadKetho(KETHO_DIR), META)
  A.eq(Serialize.dump(again.manifest), Serialize.dump(manifest))
  A.eq(Serialize.dump(again.globals), Serialize.dump(globals))
  A.eq(Serialize.dump(again.files), Serialize.dump(result.files))
end

return function()
  test_argument_is_normalized_with_lua_type()
  test_secret_when_flag_becomes_a_when_condition()
  test_secret_arguments_are_copied()
  test_default_true_is_kept()
  test_default_false_is_kept()
  test_absent_default_stays_absent()
  test_function_level_secure_only_is_marked()
  test_system_level_secure_only_is_inherited_under_namespaced_key()
  test_unrestricted_function_omits_secure_only()
  test_secret_returns_true_is_always()
  test_function_without_secret_flags_never_returns_secrets()
  test_may_return_nothing_is_kept()
  test_never_secret_return_is_marked()
  test_widget_method_is_protected()
  test_widget_method_const_secret_accessor_is_kept()
  test_widget_methods_stay_out_of_functions()
  test_script_object_tables_stay_out_of_structs()
  test_type_defined_only_in_script_object_maps_to_any_and_is_reported()
  test_event_is_keyed_by_literal_name()
  test_secret_in_chat_messaging_lockdown_becomes_a_when_condition()
  test_enum_fields_and_meta_are_collected()
  test_constants_are_resolved()
  test_enum_typed_string_constant_becomes_the_enum_value()
  test_struct_fields_map_enum_types_to_number()
  test_meta_fields_are_copied()
  test_files_group_parts_by_source_file()
  test_file_that_produces_nothing_is_skipped()
  test_global_api_name_absent_from_docs_lands_in_globals_api()
  test_global_api_name_present_in_docs_stays_out_of_globals_api()
  test_lua_api_names_land_in_globals_lua()
  test_globals_frames_exclude_load_on_demand()
  test_globals_framexml_exclude_load_on_demand()
  test_globals_events_flatten_every_system()
  test_globals_widgets_is_the_ketho_table()
  test_returns_never_secret_is_carried()
  test_duplicate_key_across_files_is_reported_and_last_file_wins()
  test_fixture_docs_have_no_duplicates()
  test_ignored_doc_fields_are_counted()
  test_build_twice_dumps_byte_identical()
end

-- Macros read and edited through w.mock.macros, and RunMacroText handing each slash line to w:slash.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local function test_create_and_read_macros() -- (G17)
  G.withGame("retail", function()
    A.eq(_G.CreateMacro("Hello", 134400, "/say hi", false), 1)
    A.eq(_G.CreateMacro("Mine", 134400, "/dance", true), 121)
    A.same({ _G.GetNumMacros() }, { 1, 1 })
    A.same({ _G.GetMacroInfo(1) }, { "Hello", 134400, "/say hi" })
    A.same({ _G.GetMacroInfo(121) }, { "Mine", 134400, "/dance" })
    A.same({ _G.GetMacroIndexByName("Hello"), _G.GetMacroIndexByName("Nope"), _G.GetMacroBody("Mine") }, { 1, 0, "/dance" })
  end)
end

local function test_edit_and_delete() -- (G17)
  G.withGame("retail", function()
    _G.CreateMacro("Hello", 134400, "/say hi", false)
    _G.EditMacro(1, "Hi", nil, "/say yo")
    A.same({ _G.GetMacroInfo("Hi") }, { "Hi", 134400, "/say yo" })
    _G.DeleteMacro(1)
    A.same({ _G.GetNumMacros() }, { 0, 0 })
  end)
end

local function test_unknown_macro_returns_the_default_and_counts_unscripted() -- (G17)
  G.withGame("retail", function(w)
    A.eq(_G.GetMacroInfo(5), nil)
    A.eq(_G.GetMacroIndexByName("Nope"), 0)
    A.eq(w.unscripted.GetMacroInfo, 1)
    A.eq(w.unscripted.GetMacroIndexByName, 1)
  end)
end

local function test_macros_come_from_the_mock() -- (G17)
  G.withGame("retail", function(w)
    w:setMock({ macros = { account = { { name = "A", icon = 1, body = "/a" } }, character = { { name = "C", icon = 2, body = "/c" } } } })
    A.same({ _G.GetNumMacros() }, { 1, 1 })
    A.same({ _G.GetMacroInfo(121) }, { "C", 2, "/c" })
  end)
end

local function test_a_full_list_refuses_the_macro_and_counts_unscripted() -- (G17)
  G.withGame("retail", function(w)
    for i = 1, 120 do
      A.eq(_G.CreateMacro("m" .. i, 1, "/x", false), i)
    end
    A.eq(_G.CreateMacro("over", 1, "/x", false), nil)
    A.eq(w.unscripted.CreateMacro, 1)
    A.eq((_G.GetNumMacros()), 120)
    for i = 1, 30 do
      A.eq(_G.CreateMacro("c" .. i, 1, "/x", true), 120 + i)
    end
    A.eq(_G.CreateMacro("over", 1, "/x", true), nil)
  end)
end

local function test_character_macro_limit_is_18_off_retail_assumed() -- (G17)
  G.withGame("vanilla", function()
    for _ = 1, 18 do
      A.truthy(_G.CreateMacro("c", 1, "/x", true))
    end
    A.eq(_G.CreateMacro("over", 1, "/x", true), nil)
  end)
end

local function test_run_macro_text_sends_slash_lines_to_handlers() -- (G17)
  G.withGame("retail", function(w)
    require("framexml.fakes.slash").install(w)
    local hits = {}
    _G.SlashCmdList.T = function(msg)
      hits[#hits + 1] = msg
    end
    _G.SLASH_T1 = "/t"
    _G.C_Macro.RunMacroText("/t one\nnot a command\n/t two")
    A.same(hits, { "one", "two" })
    _G.CreateMacro("Run", 1, "#showtooltip\n/t three", false)
    _G.RunMacro("Run")
    _G.RunMacro(1)
    A.same(hits, { "one", "two", "three", "three" })
  end)
end

-- A world without the slash fake (framexml/fakes/slash.lua) cannot run a slash line, so the call counts as unscripted
-- instead of doing nothing unnoticed; a text without slash lines needs no slash fake.
local function test_run_macro_text_without_the_slash_fake_counts_unscripted()
  G.withGame("retail", function(w)
    A.eq(w.slash, nil)
    _G.C_Macro.RunMacroText("plain text")
    A.eq(w.unscripted["C_Macro.RunMacroText"], nil)
    _G.C_Macro.RunMacroText("/t one\n/t two")
    _G.CreateMacro("Run", 1, "/t three", false)
    _G.RunMacro(1)
    A.same({ w.unscripted["C_Macro.RunMacroText"], w.unscripted.RunMacro }, { 1, 1 })
  end)
end

local function test_bare_run_macro_text_exists_on_no_flavor() -- (G1)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      A.eq(rawget(_G, "RunMacroText"), nil, flavor)
      A.eq(type(_G.C_Macro.RunMacroText), "function", flavor)
    end)
  end
end

local function test_macro_icon_lists_assumed() -- (G17)
  G.withGame("retail", function(w)
    A.same(_G.GetMacroIcons({}), { 134400 })
    A.same(_G.GetMacroItemIcons({}), { 134400 })
    w:setMock({ macroIcons = { 7 } })
    local icons = {}
    _G.GetMacroIcons(icons)
    A.same(icons, { 7 })
  end)
end

return function()
  test_create_and_read_macros()
  test_edit_and_delete()
  test_unknown_macro_returns_the_default_and_counts_unscripted()
  test_macros_come_from_the_mock()
  test_a_full_list_refuses_the_macro_and_counts_unscripted()
  test_character_macro_limit_is_18_off_retail_assumed()
  test_run_macro_text_sends_slash_lines_to_handlers()
  test_run_macro_text_without_the_slash_fake_counts_unscripted()
  test_bare_run_macro_text_exists_on_no_flavor()
  test_macro_icon_lists_assumed()
end

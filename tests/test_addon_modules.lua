-- File modules (row L9): a loaded Lua file's return value is what import answers, by a path relative to the importing
-- file's folder (".x") or by addon name. Shapes from forever 70862 Blizzard_GamepadActionBars (PageUnit.lua:1 imports
-- ".TargetActionBars.Shared"; TargetActionBars/StaticOverrideActionBar.lua:1 imports ".Shared").
local A = require("assert")
local Addon = require("addon")
local FrameXML = require("tests.helpers.framexml")
local Tmp = require("tests.helpers.tmp")
local Xml = require("ui.xml")
local fs = require("fs")

local FILES = {
  ["Ui.xml"] = '<Ui><Script file="Bars/Shared.lua"/><Script file="Bars/Override.lua"/><Script file="Page.lua"/></Ui>',
  ["Bars/Shared.lua"] = "return { name = 'shared' }",
  ["Bars/Override.lua"] = "local _, ns = ...; ns.fromSibling = import('.Shared').name",
  ["Page.lua"] = "local _, ns = ...; ns.fromRoot = import('.Bars.Shared').name; ns.byName = import('ModT.bars.shared').name;"
    .. " ns.missing = select(2, pcall(import, '.Nope'))",
}

local function withModules(fn)
  local root = Tmp.dir("modules") .. "/ModT"
  for relative, text in pairs(FILES) do
    fs.mkdirp((root .. "/" .. relative):match("^(.*)/[^/]*$"))
    fs.writeFile(root .. "/" .. relative, text)
  end
  FrameXML.withFrameXML("forever", function(w)
    fn(w, Addon.context(w, "ModT", root))
  end)
end

local function test_import_answers_a_files_return_value_by_relative_or_addon_path_assumed()
  withModules(function(w, ctx)
    Xml.loadFile(w, "Ui.xml", ctx)
    A.same({ ctx.ns.fromSibling, ctx.ns.fromRoot, ctx.ns.byName }, { "shared", "shared", "shared" })
    A.contains(ctx.ns.missing, "import: no module '.Nope'")
    A.same(w.errors, {})
  end)
end

return function()
  test_import_answers_a_files_return_value_by_relative_or_addon_path_assumed()
end

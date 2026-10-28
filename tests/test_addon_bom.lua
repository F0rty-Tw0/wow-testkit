-- A UTF-8 byte order mark at the start of an addon's Lua file (row L7).
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local fs = require("fs")

local BOM = "\239\187\191"

-- Loads addon "Bom" whose only file Core.lua holds source; returns its error messages and its namespace.
local function loadBom(source)
  local root = Tmp.dir("bom") .. "/Bom"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Bom.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  local errors, ns = {}, nil
  HF.withFrameXML("retail", function(w)
    ns = Addon.load(w, { name = "Bom", root = root })
    for i, entry in ipairs(w.errors) do
      errors[i] = tostring(entry.message)
    end
  end)
  return errors, ns
end

local function test_a_lua_file_starting_with_a_utf8_bom_loads()
  local errors, ns = loadBom(BOM .. "local _, ns = ...\nns.ok = true\n")
  A.same({ errors, ns.ok }, { {}, true })
end

local function test_an_error_after_the_bom_names_the_files_own_line()
  local errors = loadBom(BOM .. "\nerror('two')\n")
  A.eq(errors[1], "addon:Bom/Core.lua:2: two")
end

local function test_a_bom_inside_the_file_is_still_a_syntax_error_assumed()
  local errors = loadBom("local a = 1\n" .. BOM .. "local b = 2\n")
  -- The lexer's wording depends on the C library's ctype ("'=' expected" on Windows, "unexpected symbol" on Linux).
  A.contains(errors[1], "addon:Bom/Core.lua:2: ")
  A.contains(errors[1], " near ")
end

return function()
  test_a_lua_file_starting_with_a_utf8_bom_loads()
  test_an_error_after_the_bom_names_the_files_own_line()
  test_a_bom_inside_the_file_is_still_a_syntax_error_assumed()
end

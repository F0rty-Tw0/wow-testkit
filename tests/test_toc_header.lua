-- Which game UIs an addon's own TOC header lets it load in (TocHeader.loadsOn). Pure: also runs on the system Lua.
local A = require("assert")
local Toc = require("toc")
local TocHeader = require("toc_header")

local function loadsOn(header, flavor)
  return TocHeader.loadsOn(Toc.parse(header .. "\nCore.lua\n").meta, flavor)
end

local function test_no_header_loads_everywhere()
  A.same({ loadsOn("## Title: X", "retail") }, { true })
end

-- source: row BU26.
local function test_allow_load_glue_keeps_the_addon_out_of_the_game_ui()
  A.same({ loadsOn("## AllowLoad: Glue", "retail") }, { false, "glue screen" })
  A.same({ loadsOn("## AllowLoad: Game", "retail") }, { true })
  A.same({ loadsOn("## AllowLoad: Both", "retail") }, { true })
end

-- source: row BU26 (assumed: the trailing game-type list limits the directive).
local function test_allow_load_glue_applies_only_on_the_listed_game_types_assumed()
  A.same({ loadsOn("## AllowLoad: Glue [AllowLoadGameType vanilla]", "vanilla") }, { false, "glue screen" })
  A.same({ loadsOn("## AllowLoad: Glue [AllowLoadGameType vanilla]", "retail") }, { true })
end

-- source: rows BU8, L8 (assumed).
local function test_game_type_headers_allow_and_exclude_assumed()
  A.same({ loadsOn("## AllowLoadGameType: vanilla, tbc", "retail") }, { false, "game type" })
  A.same({ loadsOn("## AllowLoadGameType: vanilla, tbc", "tbc") }, { true })
  A.same({ loadsOn("## ExcludeLoadGameType: mainline", "retail") }, { false, "game type" })
  A.same({ loadsOn("## ExcludeLoadGameType: mainline", "vanilla") }, { true })
end

return function()
  test_no_header_loads_everywhere()
  test_allow_load_glue_keeps_the_addon_out_of_the_game_ui()
  test_allow_load_glue_applies_only_on_the_listed_game_types_assumed()
  test_game_type_headers_allow_and_exclude_assumed()
end

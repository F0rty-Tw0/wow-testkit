-- TOC file-line variables ([Family], [Game]) in any addon's TOC. Pure: also runs on the system Lua.
local A = require("assert")
local Toc = require("toc")

local TOC = "Modules\\Extension_[Game].xml\n[Family]\\Core.lua\n"

local function filesOn(flavor)
  return (Toc.filesFor(Toc.parse(TOC), flavor))
end

-- source: confirmed (row BU3) wiki TOC_format: [Family] "Mainline, or Classic", [Game] "Standard, Vanilla, Camelot, TBC,
-- Wrath, or Mists"; Plumber.toc:71 `Modules\GameTooltipExtension_[Game].xml` ships GameTooltipExtension_Standard.xml.
local function test_family_and_game_expand_per_flavor()
  A.same(filesOn("retail"), { "Modules/Extension_Standard.xml", "Mainline/Core.lua" })
  A.same(filesOn("forever"), { "Modules/Extension_Camelot.xml", "Mainline/Core.lua" })
  A.same(filesOn("mists"), { "Modules/Extension_Mists.xml", "Classic/Core.lua" })
  A.same(filesOn("vanilla"), { "Modules/Extension_Vanilla.xml", "Classic/Core.lua" })
  A.same(filesOn("tbc"), { "Modules/Extension_TBC.xml", "Classic/Core.lua" })
end

return function()
  test_family_and_game_expand_per_flavor()
end

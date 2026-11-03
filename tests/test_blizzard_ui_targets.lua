-- The Blizzard UI layer's default targets (blizzard_ui.lua M.TARGETS): what a load with no opts.targets brings in. The
-- extract is a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")

-- Blizzard_EditMode's login layout pass indexes OverrideActionBar.xpBar (retail editmodemanager.lua:641); without the
-- addon the pass stops there and the main action bar never leaves the top-left corner.
local function test_default_targets_load_the_override_action_bar()
  local oab = { toc = "## Interface: 120100\noab.lua\n", files = { ["oab.lua"] = "OverrideActionBar = {}\n" } }
  local addons = B.mini({ blizzard_overrideactionbar = oab })
  B.run(addons, {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_OverrideActionBar")
    A.eq(type(_G.OverrideActionBar), "table")
  end)
end

return function()
  test_default_targets_load_the_override_action_bar()
end

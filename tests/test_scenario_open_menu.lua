-- The openMenu step's argument checks. Split from test_scenario_menu.lua (size).
local A = require("assert")
local Scenario = require("scenario")

local ADDONS_DIR = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or ".") .. "/fixtures/addons"

-- A retail scenario world (no login), always destroyed.
local function withMenuScenario(fn)
  local s = Scenario.new({ addon = "Hover", root = ADDONS_DIR .. "/Hover", flavor = "retail" })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_open_menu_with_a_non_string_which_names_the_scenario_line()
  withMenuScenario(function(s)
    local message = A.errors(function()
      s:openMenu(nil, {})
    end, "openMenu: which must be a string, got nil")
    A.contains(message, "test_scenario_open_menu.lua:")
    A.eq(#s.w.menus, 0)
  end)
end

return function()
  test_open_menu_with_a_non_string_which_names_the_scenario_line()
end

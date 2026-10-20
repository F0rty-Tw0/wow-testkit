-- Menu scenario test helpers: a retail scenario world on the Hover fixture.
local Scenario = require("scenario")

local M = {}

local TESTS_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/helpers/[^/]*$") or "tests"
local MENU_ADDONS_DIR = TESTS_DIR .. "/fixtures/addons"

-- A retail scenario world (no login), always destroyed.
function M.withMenuScenario(fn)
  local s = Scenario.new({ addon = "Hover", root = MENU_ADDONS_DIR .. "/Hover", flavor = "retail" })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

return M

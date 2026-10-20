-- Clicky fixture helpers for scenario tests: its paths, a temp copy to write goldens into, and golden reading.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local M = {}

local TESTS_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/helpers/[^/]*$") or "tests"
local GOLDEN_SUBDIR = "/tests/scenarios/golden/input/" -- scenarioName("scn_input.lua") is "input"

M.ROOT = TESTS_DIR .. "/fixtures/addons/Clicky"
M.INPUT_SCENARIO = TESTS_DIR .. "/fixtures/scenarios/scn_input.lua"

local function copyTree(from, to)
  fs.mkdirp(to)
  for _, name in ipairs(fs.list(from)) do
    if fs.isdir(from .. "/" .. name) then
      copyTree(from .. "/" .. name, to .. "/" .. name)
    else
      fs.writeFile(to .. "/" .. name, assert(fs.readFile(from .. "/" .. name)))
    end
  end
end

-- A temp copy of the Clicky fixture; returns its root. Scenario goldens go here, never into the repo.
function M.clickyCopy()
  local root = Tmp.dir("clicky")
  copyTree(M.ROOT, root)
  return root
end

-- The golden `name` of the scn_input scenario for `flavor` under root, as a list of lines with color runs
-- ("[rrggbb]") stripped, so tests pin structure, not label colors.
function M.goldenLines(root, name, flavor)
  local text = fs.readFile(root .. GOLDEN_SUBDIR .. name .. "." .. flavor .. ".txt")
  A.truthy(text, "golden " .. name .. "." .. flavor .. " written")
  local out = {}
  for line in text:gsub("%[%x%x%x%x%x%x%]", ""):gmatch("[^\n]+") do
    out[#out + 1] = line
  end
  return out
end

return M

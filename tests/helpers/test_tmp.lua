local A = require("assert")
local fs = require("fs")
local Tmp = require("tests.helpers.tmp")

local function test_dir_skips_a_name_that_already_exists()
  math.randomseed(7)
  local first = Tmp.dir("tmp")
  math.randomseed(7)
  local second = Tmp.dir("tmp")
  A.truthy(first ~= second, first)
  A.truthy(fs.isdir(first) and fs.isdir(second), second)
end

local function test_dir_names_the_prefix_under_the_temp_folder()
  local dir = Tmp.dir("cli")
  A.truthy(dir:find("/wow-testkit-cli-", 1, true), dir)
  A.eq(dir:find("\\", 1, true), nil)
end

return function()
  test_dir_skips_a_name_that_already_exists()
  test_dir_names_the_prefix_under_the_temp_folder()
end

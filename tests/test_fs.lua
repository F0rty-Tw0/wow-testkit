local A = require("assert")
local fs = require("fs")

math.randomseed(os.time())

local function tempDir()
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  return base .. "/wow-testkit-" .. os.time() .. "-" .. math.random(1, 1000000)
end

local function test_mkdirp_creates_nested_dirs_and_write_then_list_finds_file()
  local dir = tempDir() .. "/a/b"
  fs.mkdirp(dir)
  fs.writeFile(dir .. "/x.txt", "hi")
  A.same(fs.list(dir), { "x.txt" })
  A.truthy(fs.exists(dir .. "/x.txt"), "file exists")
  A.truthy(fs.isdir(dir), "dir is a dir")
  A.eq(fs.isdir(dir .. "/x.txt"), false, "file is not a dir")
  A.eq(fs.readFile(dir .. "/x.txt"), "hi")
end

local function test_mkdirp_tolerates_existing_dir()
  local dir = tempDir()
  fs.mkdirp(dir)
  fs.mkdirp(dir)
  A.truthy(fs.isdir(dir), "still a dir")
end

local function test_exists_is_false_for_missing_path()
  A.eq(fs.exists(tempDir() .. "/missing"), false)
end

return function()
  test_mkdirp_creates_nested_dirs_and_write_then_list_finds_file()
  test_mkdirp_tolerates_existing_dir()
  test_exists_is_false_for_missing_path()
end

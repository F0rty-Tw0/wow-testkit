local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local function tempDir()
  return Tmp.dir("fs")
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

-- Addon code may clear the global os. Under run51 the bridge serves these calls; the pure run (no bridge) goes
-- through os.rename and os.execute.
local function test_dir_calls_work_while_the_global_os_is_cleared()
  local dir, hostOs = tempDir(), os
  rawset(_G, "os", nil)
  local ok, err = pcall(function()
    fs.mkdirp(dir .. "/a/b")
    A.eq(fs.mkdir(dir .. "/c"), true)
    A.same({ fs.isdir(dir .. "/a/b"), fs.exists(dir .. "/c") }, { true, true })
  end)
  rawset(_G, "os", hostOs)
  assert(ok, err)
end

local function test_mkdir_creates_once_then_reports_an_existing_dir()
  local dir = tempDir() .. "/once"
  A.eq(fs.mkdir(dir), true)
  A.eq(fs.mkdir(dir), false)
  A.truthy(fs.isdir(dir), "created")
end

local function test_mkdir_raises_when_the_dir_cannot_be_created()
  local dir = tempDir()
  fs.writeFile(dir .. "/file", "x")
  A.errors(function()
    fs.mkdir(dir .. "/file/sub")
  end, "file/sub")
end

local function test_exists_is_false_for_missing_path()
  A.eq(fs.exists(tempDir() .. "/missing"), false)
end

return function()
  test_mkdirp_creates_nested_dirs_and_write_then_list_finds_file()
  test_mkdir_creates_once_then_reports_an_existing_dir()
  test_mkdir_raises_when_the_dir_cannot_be_created()
  test_mkdirp_tolerates_existing_dir()
  test_exists_is_false_for_missing_path()
  test_dir_calls_work_while_the_global_os_is_cleared()
end

local A = require("assert")
local Home = require("home")

local function fakeGetenv(vars)
  return function(name)
    return vars[name]
  end
end

local function test_dir_uses_testkit_home_with_forward_slashes()
  A.eq(Home.dir(fakeGetenv({ TESTKIT_HOME = "C:\\x\\y", LOCALAPPDATA = "C:\\other" })), "C:/x/y")
end

local function test_dir_uses_localappdata_on_windows()
  A.eq(Home.dir(fakeGetenv({ LOCALAPPDATA = "C:\\Users\\me\\AppData\\Local", HOME = "/home/me" })), "C:/Users/me/AppData/Local/wow-testkit")
end

local function test_dir_uses_home_cache_elsewhere()
  A.eq(Home.dir(fakeGetenv({ HOME = "/home/me" })), "/home/me/.cache/wow-testkit")
end

local function test_dir_errors_naming_testkit_home_when_nothing_resolves()
  A.errors(function()
    Home.dir(fakeGetenv({}))
  end, "TESTKIT_HOME")
end

local function test_path_joins_segments_onto_dir()
  A.eq(Home.path("api", "retail.lua"), Home.dir() .. "/api/retail.lua")
end

return function()
  test_dir_uses_testkit_home_with_forward_slashes()
  test_dir_uses_localappdata_on_windows()
  test_dir_uses_home_cache_elsewhere()
  test_dir_errors_naming_testkit_home_when_nothing_resolves()
  test_path_joins_segments_onto_dir()
end

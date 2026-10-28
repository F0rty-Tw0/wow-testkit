-- SessionHost and WTF: the copy-once import of a new session's saved.lua, and the reimport that replaces it on request.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Saved = require("session_saved")
local SessionHost = require("session_host")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local KEPT = "wtf: kept the session's saved.lua; use Re-import to replace it"

local function drained(host)
  return Json.decode(host:drain())
end

-- A WtfDemo account file holding `WtfDemoDB = { n = <n> }`; returns its path.
local function accountFile(n)
  local path = Tmp.dir("wtfhost") .. "/acc.lua"
  fs.writeFile(path, "WtfDemoDB = { n = " .. n .. " }")
  return path
end

-- The names of the events in the outbox, console lines left out.
local function eventNames(host)
  local names = {}
  for _, entry in ipairs(drained(host)) do
    if entry.event ~= "console" then
      names[#names + 1] = entry.event
    end
  end
  return names
end

-- The text of every console line in the outbox.
local function consoleLines(host)
  local lines = {}
  for _, entry in ipairs(drained(host)) do
    if entry.event == "console" then
      lines[#lines + 1] = entry.data.text
    end
  end
  return lines
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local function test_wtf_import_copies_once()
  local dir, acc = Tmp.dir("wtfsession"), accountFile(1)
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function(host)
    A.eq(host.wtf.account, acc)
    A.same(Saved.read(dir), { WtfDemoDB = { n = 1 } })
    A.eq(_G.WtfDemoDB.n, 1)
    A.eq(contains(consoleLines(host), KEPT), false)
  end)
  fs.writeFile(acc, "WtfDemoDB = { n = 5 }")
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function(host)
    A.eq(_G.WtfDemoDB.n, 1)
    A.eq(contains(consoleLines(host), KEPT), true, "the skipped import says so")
  end)
end

local function test_reimport_overwrites_and_discards_live_changes()
  local dir, acc = Tmp.dir("wtfsession"), accountFile(1)
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function(host)
    host:handleJson("slash", '{"text":"/run WtfDemoDB.n = 99"}')
    A.eq(_G.WtfDemoDB.n, 99)
    fs.writeFile(acc, "WtfDemoDB = { n = 7 }")
    host:drain()
    local reply = Json.decode(host:handleJson("reimport", "{}"))
    A.same({ reply.ok, reply.loads, reply.warnings }, { true, 2, 0 })
    A.eq(_G.WtfDemoDB.n, 7)
    A.same(Saved.read(dir), { WtfDemoDB = { n = 7 } })
    A.same(eventNames(host), { "reload", "snapshot" })
  end)
end

local function test_reimport_takes_the_paths_of_the_request()
  local root = Tmp.dir("wtfroot")
  local acc, char = root .. "/acc.lua", root .. "/Realm/Char/char.lua"
  fs.writeFile(acc, "WtfDemoDB = { n = 1 }")
  fs.mkdirp(root .. "/Realm/Char")
  fs.writeFile(char, "WtfDemoCharDB = { c = 4 }")
  H.withHost({ addonDir = H.WTF, wtf = { account = acc }, wtfRoot = root }, function(host)
    A.eq(_G.WtfDemoCharDB, nil)
    local req = Json.encode({ wtf = { account = acc, character = char } })
    A.eq(Json.decode(host:handleJson("reimport", req)).ok, true)
    A.same(_G.WtfDemoCharDB, { c = 4 })
    fs.writeFile(char, "WtfDemoCharDB = { c = 8 }")
    A.eq(Json.decode(host:handleJson("reimport", "{}")).ok, true)
    A.same(_G.WtfDemoCharDB, { c = 8 }, "a later reimport keeps the new paths")
  end)
end

local function test_reimport_refuses_malformed_paths()
  H.withHost({ addonDir = H.WTF, wtf = { account = accountFile(1) } }, function(host)
    local want = { ok = false, error = "malformed request: wtf must be { account?, character? } paths" }
    A.same(Json.decode(host:handleJson("reimport", '{"wtf":"x"}')), want)
    A.same(Json.decode(host:handleJson("reimport", '{"wtf":{"other":"x"}}')), want)
    A.same(Json.decode(host:handleJson("reimport", '{"wtf":{"account":1}}')), want)
  end)
end

local OUTSIDE = { ok = false, error = "malformed request: wtf paths must stay inside the WTF folder" }

local function reimportWith(host, wtf)
  return Json.decode(host:handleJson("reimport", Json.encode({ wtf = wtf })))
end

local function test_reimport_refuses_paths_outside_the_wtf_folder()
  local root = Tmp.dir("wtfroot")
  local inside, outside = root .. "/acc.lua", accountFile(5)
  fs.writeFile(inside, "WtfDemoDB = { n = 1 }")
  local escapes = {
    outside,
    root .. "/../" .. outside:match("([^/]+/[^/]+)$"),
    (root .. "\\..\\x\\acc.lua"),
    root .. "x/acc.lua",
    "../acc.lua",
    root .. "/a/../../acc.lua",
    root .. "/..",
  }
  H.withHost({ addonDir = H.WTF, wtf = { account = inside }, wtfRoot = root }, function(host)
    for _, path in ipairs(escapes) do
      A.same(reimportWith(host, { account = path }), OUTSIDE, path)
      A.same(reimportWith(host, { account = inside, character = path }), OUTSIDE, path)
    end
    A.eq(host.wtf.account, inside, "a refused request keeps the paths")
    A.eq(_G.WtfDemoDB.n, 1)
    A.eq(reimportWith(host, { account = (inside:gsub("/", "\\")) }).ok, true, "backslashes")
  end)
end

-- Windows paths ignore case; elsewhere a sibling folder differing only in case is outside.
local function test_reimport_prefix_folds_case_only_on_windows()
  local root = Tmp.dir("wtfcase")
  local upper = { account = root:upper() .. "/acc.lua" }
  local real = SessionHost.foldCase
  H.withHost({ addonDir = H.WTF, wtf = { account = root .. "/acc.lua" }, wtfRoot = root }, function(host)
    SessionHost.foldCase = false
    local strict = reimportWith(host, upper)
    SessionHost.foldCase = true
    local folded = reimportWith(host, upper)
    SessionHost.foldCase = real
    A.same(strict, OUTSIDE)
    A.eq(folded.ok, true)
  end)
  A.eq(real, package.config:sub(1, 1) == "\\")
end

local function test_reimport_paths_need_a_wtf_root()
  local acc = accountFile(1)
  H.withHost({ addonDir = H.WTF, wtf = { account = acc } }, function(host)
    A.same(reimportWith(host, { account = acc }), OUTSIDE)
    A.eq(Json.decode(host:handleJson("reimport", "{}")).ok, true, "the paths the host opened with still work")
  end)
end

-- A WTF folder whose one account holds files (path under Account/ACC -> text); returns its path.
local function wtfDir(files)
  local dir = Tmp.dir("wtfdir")
  for path, text in pairs(files) do
    local full = dir .. "/Account/ACC/" .. path
    fs.mkdirp(full:match("^(.*)/[^/]*$"))
    fs.writeFile(full, text)
  end
  return dir
end

-- A temp addon WtfProbe that saves WtfProbeDB and copies the CVar wtfProbe into WtfProbeSeen when it loads.
local function probeAddon()
  local root = Tmp.dir("wtfprobe") .. "/WtfProbe"
  fs.mkdirp(root)
  fs.writeFile(root .. "/WtfProbe.toc", "## Interface: 120100\n## SavedVariables: WtfProbeDB\nMain.lua\n")
  fs.writeFile(root .. "/Main.lua", 'WtfProbeSeen = GetCVar("wtfProbe")\n')
  return root
end

local function test_wtf_dir_applies_before_login_and_on_every_reload()
  local dir = wtfDir({
    ["config-cache.wtf"] = 'SET wtfProbe "on"\n',
    ["bindings-cache.wtf"] = "bind K PROBE_TOGGLE\n",
    ["SavedVariables/WtfProbe.lua"] = "WtfProbeDB = { n = 2 }\n",
  })
  H.withHost({ addonDir = probeAddon(), wtfDir = dir }, function(host)
    A.eq(host.wtf.account, dir .. "/Account/ACC/SavedVariables/WtfProbe.lua")
    A.eq(_G.WtfProbeSeen, "on", "the addon reads the CVar while it loads")
    A.same(_G.WtfProbeDB, { n = 2 })
    A.eq(_G.GetBindingAction("K"), "PROBE_TOGGLE")
    rawset(_G, "WtfProbeSeen", nil)
    A.eq(Json.decode(host:handleJson("reload", "{}")).ok, true)
    A.eq(_G.WtfProbeSeen, "on", "a reload applies the import again")
    A.eq(_G.GetBindingAction("K"), "PROBE_TOGGLE")
  end)
end

local function test_wtf_dir_that_cannot_open_is_a_console_line()
  local dir = wtfDir({ ["config-cache.wtf"] = 'SET wtfProbe "on"\n' })
  fs.mkdirp(dir .. "/Account/ACC2")
  H.withHost({ addonDir = probeAddon(), wtfDir = dir }, function(host)
    local lines = consoleLines(host)
    A.eq(contains(lines, "wtf: several accounts: ACC, ACC2; pass --wtf-account"), true)
    A.eq(_G.WtfProbeSeen, nil)
    A.eq(host.wtf, nil)
  end)
  H.withHost({ addonDir = probeAddon(), wtfDir = dir, wtfAccount = "ACC" }, function()
    A.eq(_G.WtfProbeSeen, "on")
  end)
end

local function test_reimport_without_wtf_replies_an_error()
  H.withHost(nil, function(host)
    A.same(Json.decode(host:handleJson("reimport", "{}")), { ok = false, error = "no WTF folder picked" })
    local req = Json.encode({ wtf = { account = accountFile(1) } })
    A.same(Json.decode(host:handleJson("reimport", req)), { ok = false, error = "no WTF folder picked" })
  end)
end

local function test_reimport_needs_a_session_folder()
  local host = SessionHost.new({ addonDir = H.WTF, flavor = "retail", wtf = { account = accountFile(1) } })
  local reply = Json.decode(host:handleJson("reimport", "{}"))
  host:shutdown()
  A.same(reply, { ok = false, error = "no session folder" })
end

local function test_wtf_warnings_reach_the_console()
  local acc = accountFile(1)
  fs.writeFile(acc, "WtfDemoDB = {")
  H.withHost({ addonDir = H.WTF, wtf = { account = acc } }, function(host)
    local first
    for _, text in ipairs(consoleLines(host)) do
      first = first or (text:sub(1, 4) == "wtf:" and text)
    end
    A.truthy(first, "no wtf: console line")
  end)
end

return function()
  test_wtf_import_copies_once()
  test_reimport_overwrites_and_discards_live_changes()
  test_reimport_takes_the_paths_of_the_request()
  test_reimport_refuses_malformed_paths()
  test_reimport_refuses_paths_outside_the_wtf_folder()
  test_reimport_prefix_folds_case_only_on_windows()
  test_reimport_paths_need_a_wtf_root()
  test_wtf_dir_applies_before_login_and_on_every_reload()
  test_wtf_dir_that_cannot_open_is_a_console_line()
  test_reimport_without_wtf_replies_an_error()
  test_reimport_needs_a_session_folder()
  test_wtf_warnings_reach_the_console()
end

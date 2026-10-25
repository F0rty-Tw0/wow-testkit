-- SessionHost and WTF: the copy-once import of a new session's saved.lua, and the reimport that replaces it on request.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Saved = require("session_saved")
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
  local acc = accountFile(1)
  local char = Tmp.dir("wtfchar") .. "/char.lua"
  fs.writeFile(char, "WtfDemoCharDB = { c = 4 }")
  H.withHost({ addonDir = H.WTF, wtf = { account = acc } }, function(host)
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

local function test_reimport_without_wtf_replies_an_error()
  H.withHost(nil, function(host)
    A.same(Json.decode(host:handleJson("reimport", "{}")), { ok = false, error = "no WTF folder picked" })
    local req = Json.encode({ wtf = { account = accountFile(1) } })
    A.same(Json.decode(host:handleJson("reimport", req)), { ok = false, error = "no WTF folder picked" })
  end)
end

local function test_reimport_needs_a_session_folder()
  local SessionHost = require("session_host")
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
  test_reimport_without_wtf_replies_an_error()
  test_reimport_needs_a_session_folder()
  test_wtf_warnings_reach_the_console()
end

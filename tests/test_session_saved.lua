-- Session persistence: SavedVariables written at reload and shutdown and read back at the next load, the logout and
-- reloading-login events, mock state and console lines kept across a reload, and a reload that survives a broken addon.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Saved = require("session_saved")
local Session = require("session")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local LABEL_BODY = [[
local frame = CreateFrame("Frame", "BrokeFrame", UIParent)
frame:SetSize(50, 20)
frame:SetPoint("CENTER")
local text = frame:CreateFontString("BrokeText")
text:SetFont("Fonts/FRIZQT__.TTF", 14, "")
text:SetPoint("CENTER")
text:SetText("here")
]]

local LOG_BODY = [[
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, isInitial, isReloading)
  LogDB = LogDB or {}
  local entry = event == "PLAYER_LOGOUT" and "LOGOUT" or ("PEW:" .. tostring(isInitial) .. ":" .. tostring(isReloading))
  LogDB[#LogDB + 1] = entry
end)
]]

-- Reloads sess and runs fn(fresh); the fresh session is always shut down.
local function reloaded(sess, over, fn)
  local fresh = Session.reload(sess, over)
  local ok, err = pcall(fn, fresh)
  fresh:shutdown()
  if not ok then
    error(err, 0)
  end
end

local function consoleLines(sess, kind)
  local out = {}
  for _, line in ipairs(sess:call("console", { since = 0 }).lines) do
    if line.kind == kind then
      out[#out + 1] = line.text
    end
  end
  return out
end

local function test_reload_keeps_saved_variables()
  H.withSession(nil, function(sess)
    local dir = sess.opts.sessionDir
    A.eq(_G.SessionDemoDB.runs, 1)
    reloaded(sess, nil, function()
      A.eq(_G.SessionDemoDB.runs, 2)
      A.same(Saved.read(dir), { SessionDemoDB = { runs = 1 } })
    end)
    A.same(Saved.read(dir), { SessionDemoDB = { runs = 2 } })
  end)
end

local function test_new_session_reads_the_file_a_restart()
  local dir = Tmp.dir("savedrestart")
  H.withSession({ sessionDir = dir }, function(sess)
    reloaded(sess, nil, function() end)
  end)
  H.withSession({ sessionDir = dir }, function()
    A.eq(_G.SessionDemoDB.runs, 3)
  end)
end

local function test_unserialisable_variable_is_skipped_with_a_console_line()
  H.withSession(nil, function(sess)
    local dir = sess.opts.sessionDir
    _G.SessionDemoDB.fn = print
    reloaded(sess, nil, function(fresh)
      A.same(Saved.read(dir), { SessionDemoDB = { runs = 1 } })
      A.contains(consoleLines(fresh, "system")[1], "SessionDemoDB.fn")
      A.eq(_G.SessionDemoDB.runs, 2)
      A.eq(fresh:call("slash", { text = "/sdemo alive" }).handled, true)
    end)
  end)
end

local function test_corrupt_saved_file_is_ignored_with_a_warning()
  local dir = Tmp.dir("savedcorrupt")
  fs.writeFile(dir .. "/saved.lua", "{{{")
  H.withSession({ sessionDir = dir }, function(sess)
    A.eq(_G.SessionDemoDB.runs, 1)
    A.eq(consoleLines(sess, "system")[1]:sub(1, 23), "saved variables ignored")
  end)
end

local function test_saved_file_drops_what_cannot_be_written_and_names_the_paths()
  local dir = Tmp.dir("savedfile")
  local cycle = { n = 1 }
  cycle.self = cycle
  local mixed = { keep = 1, f = print, nested = { g = print, ok = 2 }, [true] = 1 }
  local saved = { Good = { 1, "two", x = true }, Func = print, Mixed = mixed, Cycle = cycle }
  local skipped = Saved.write(dir, saved)
  A.same(skipped, { "Cycle.self", "Func", "Mixed.f", "Mixed.nested.g", "Mixed[true]" })
  A.same(Saved.read(dir), { Good = { 1, "two", x = true }, Mixed = { keep = 1, nested = { ok = 2 } }, Cycle = { n = 1 } })
  A.eq(cycle.self, cycle)
  A.same({ mixed.f, mixed.nested.g, mixed[true] }, { print, print, 1 })
  A.same(Saved.read(Tmp.dir("savedempty")), {})
end

local function test_reload_fires_logout_and_reloading_login()
  local toc = "## Interface: 120100\n## SavedVariables: LogDB\nMain.lua\n"
  local root = H.tempAddon("LogAddon", LOG_BODY, { ["LogAddon.toc"] = toc })
  H.withSession({ addonDir = root }, function(sess)
    reloaded(sess, nil, function()
      A.same(_G.LogDB, { "PEW:true:false", "LOGOUT", "PEW:false:true" })
    end)
  end)
end

local function test_reload_survives_a_broken_toc()
  local root = H.tempAddon("Broke", LABEL_BODY)
  local toc = fs.readFile(root .. "/Broke.toc")
  H.withSession({ addonDir = root }, function(sess)
    A.truthy(H.item(sess:call("snapshot"), "BrokeText"))
    os.remove(root .. "/Broke.toc")
    reloaded(sess, nil, function(broken)
      A.eq(H.item(broken:call("snapshot"), "BrokeText"), nil)
      A.truthy(#consoleLines(broken, "error") > 0)
      fs.writeFile(root .. "/Broke.toc", toc)
      reloaded(broken, nil, function(back)
        A.truthy(H.item(back:call("snapshot"), "BrokeText"))
      end)
    end)
  end)
end

local function test_reload_keeps_mock_state()
  H.withSession(nil, function(sess)
    sess:call("state", { modifiers = { shift = true } })
    reloaded(sess, nil, function(fresh)
      A.eq(_G.IsShiftKeyDown(), true)
      A.eq(fresh.state.modifiers.shift, true)
    end)
  end)
end

local function test_reload_carries_console_lines_and_the_host_does_not_republish_them()
  H.withHost(nil, function(host)
    host:handleJson("slash", '{"text":"/sdemo hi"}')
    host:drain()
    host:handleJson("reload", "{}")
    A.eq(consoleLines(host.sess, "print")[1], "slash hi")
    for _, entry in ipairs(Json.decode(host:drain())) do
      A.truthy(not (entry.event == "console" and entry.data.text == "slash hi"), "console line published twice")
    end
  end)
end

local function test_slash_reload_reloads()
  H.withHost(nil, function(host)
    host:handleJson("slash", '{"text":"/reload"}')
    A.eq(host.sess.loads, 2)
    A.eq(_G.SessionDemoDB.runs, 2)
  end)
end

-- amendment 2026-10-25: keepSaved reloads what saved.lua holds instead of overwriting it with the live variables.
local function test_keep_saved_reload_discards_live_changes()
  H.withSession(nil, function(sess)
    A.eq(_G.SessionDemoDB.runs, 1)
    Saved.write(sess.opts.sessionDir, { SessionDemoDB = { runs = 41 } })
    reloaded(sess, { keepSaved = true }, function()
      A.eq(_G.SessionDemoDB.runs, 42)
    end)
  end)
  H.withHost(nil, function(host)
    local before = host.sess
    local reply = Json.decode(host:handleJson("reload", '{"keepSaved":"yes"}'))
    A.eq(reply.ok, false)
    A.contains(reply.error, "keepSaved")
    A.eq(host.sess, before)
    A.eq(host.sess.loads, 1)
  end)
end

local function test_a_write_that_fails_midway_keeps_the_earlier_file()
  local dir = Tmp.dir("saved")
  Saved.write(dir, { DemoDB = { runs = 1 } })
  local writeFile = fs.writeFile
  fs.writeFile = function(path, text)
    writeFile(path, text:sub(1, 5))
    error("disk full", 0)
  end
  local ok, err = pcall(Saved.write, dir, { DemoDB = { runs = 2 } })
  fs.writeFile = writeFile
  A.same({ ok, err }, { false, "disk full" })
  A.same(Saved.read(dir), { DemoDB = { runs = 1 } })
end

return function()
  test_reload_keeps_saved_variables()
  test_new_session_reads_the_file_a_restart()
  test_unserialisable_variable_is_skipped_with_a_console_line()
  test_corrupt_saved_file_is_ignored_with_a_warning()
  test_saved_file_drops_what_cannot_be_written_and_names_the_paths()
  test_reload_fires_logout_and_reloading_login()
  test_reload_survives_a_broken_toc()
  test_reload_keeps_mock_state()
  test_reload_carries_console_lines_and_the_host_does_not_republish_them()
  test_slash_reload_reloads()
  test_keep_saved_reload_discards_live_changes()
  test_a_write_that_fails_midway_keeps_the_earlier_file()
end

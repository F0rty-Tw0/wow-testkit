-- SessionHost: what a host (the Python server, later the browser worker) keeps for the life of its process. It holds the
-- current Session across reloads, speaks JSON on the host boundary (handleJson in, drain out) and owns the outbox of
-- events the host publishes to viewers. The host only relays text; every rule about requests lives here.
local M = {}

local Assets = require("session_assets")
local Console = require("session_console")
local Json = require("json")
local Session = require("session")
local SessionSaved = require("session_saved")
local Wtf = require("session_wtf")
local fs = require("fs")

local Host = {}
Host.__index = Host

-- Removes every Json.null below value (an array becomes holey, an object loses the key).
local function removeNulls(value)
  for key, child in pairs(value) do
    if child == Json.null then
      value[key] = nil
    elseif type(child) == "table" then
      removeNulls(child)
    end
  end
end

-- Applies the null rules to a decoded request. fire counts its args first, so trailing nulls still count: req.n.
local function prepare(method, req)
  if method ~= "fire" then
    return removeNulls(req)
  end
  local args = req.args
  if args == Json.null then
    req.args = nil
  elseif type(args) == "table" then
    req.n = #args
    removeNulls(args)
  else
    req.n = 0
  end
end

-- The decoded request table, or nil plus a message.
local function decode(reqJson)
  local ok, req = pcall(Json.decode, reqJson)
  if not ok then
    return nil, "malformed request: " .. tostring(req)
  elseif type(req) ~= "table" or req == Json.null then
    return nil, "malformed request: expected a JSON object"
  end
  return req
end

local KEPT = "wtf: kept the session's saved.lua; use Re-import to replace it"

-- Imports opts.wtf into opts.sessionDir's saved.lua when it holds none yet (copy-once: a file the session wrote wins).
-- Returns the import's warnings, or the one line saying the import was skipped.
local function importWtf(opts)
  local dir = opts.sessionDir
  if not (opts.wtf and dir) then
    return {}
  end
  local kept = fs.exists(dir .. "/" .. SessionSaved.FILE)
  if kept then
    return { KEPT }
  end

  return Wtf.seed(opts, opts.wtf)
end

-- Whether wtf is a reimport's req.wtf: absent, or { account?, character? } path strings.
local function validWtf(wtf)
  if wtf == nil then
    return true
  elseif type(wtf) ~= "table" then
    return false
  end
  for key, path in pairs(wtf) do
    local known = key == "account" or key == "character"
    if not known or type(path) ~= "string" then
      return false
    end
  end

  return true
end

-- opts: Session.new's, plus wtf = { account?, character? } paths of WTF SavedVariables files (Wtf.read). Starts the
-- session; the outbox starts with the console lines the login printed and the warnings of the WTF import.
function M.new(opts)
  local warnings = importWtf(opts)
  local sess = Session.new(opts)
  for _, warning in ipairs(warnings) do
    Console.push(sess.w, "system", warning)
  end
  local root = opts.addonDir:gsub("\\", "/"):gsub("/+$", "")
  local host = { sess = sess, outbox = {}, located = {}, consoleSeq = 0, logSeq = 0, wtf = opts.wtf, addonRoots = { [sess.folder:lower()] = root } }
  setmetatable(host, Host)
  host:collectConsole()
  return host
end

function Host:push(event, data)
  self.outbox[#self.outbox + 1] = { event = event, data = data }
end

-- Adds assets[ref].located (Assets.locate; nil leaves the key out) to a snapshot reply. Hits are kept per ref until the
-- next reload, so a snapshot every half second does not walk the folders again.
function Host:locate(reply)
  local client = self.sess.w.client
  for ref, asset in pairs(reply.assets or {}) do
    local hit = self.located[ref]
    if hit == nil then
      hit = Assets.locate(self.addonRoots, client, asset) or false
      self.located[ref] = hit
    end
    asset.located = hit or nil
  end
end

-- Queues a console event per line newer than the last one queued.
function Host:collectConsole()
  for _, line in ipairs(self.sess:call("console", { since = self.consoleSeq }).lines) do
    self:push("console", line)
    self.consoleSeq = line.seq
  end
end

-- Queues one combatlog { seq } event when the combat log (w.combat.log, from Combat.install) grew since the last call;
-- the viewer then reads the new lines through the combatlog method. A reloaded world's log counts from 0 again.
function Host:collectCombatLog()
  local c = self.sess.w.combat
  local seq = c and c.log.seq or 0
  if seq > self.logSeq then
    self:push("combatlog", { seq = seq })
  end
  self.logSeq = seq
end

-- The one place a session is swapped; req is checked by Session.reload (SessionOptions.reopen). Replies { ok = true,
-- loads, flavor, screen = { width, height } }, or { ok = false, error } with a console line saying why. A refused req
-- keeps the session (a lost one stays lost); a new world that cannot be built leaves the session reopened on its old
-- options; when that fails too the session is lost: every later call but a reload answers that error, and a reload
-- tries to open again. The new session carries the console ring, so consoleSeq stays and only lines newer than it are
-- queued.
function Host:reload(req)
  local ok, fresh, failure = pcall(Session.reload, self.sess, req)
  if not (ok and fresh) then
    local refused = not ok and tostring(fresh)
    local reason = refused or failure
    self.lost = ok and reason or self.lost
    Console.push(self.sess.w, "system", "Reload failed: " .. reason)

    return { ok = false, error = reason }
  end
  self:collectConsole()
  self.sess, self.located, self.lost = fresh, {}, nil
  self:push("reload", { loads = fresh.loads })
  self:push("snapshot", { seq = fresh.seq })
  if failure then
    local reason = failure .. " (reopened with the previous options)"
    Console.push(fresh.w, "system", "Reload failed: " .. reason)

    return { ok = false, error = reason }
  end
  local screen = { width = fresh.w.screen.width, height = fresh.w.screen.height }
  local reply = { ok = true, loads = fresh.loads, flavor = fresh.w.flavor, screen = screen }

  return reply
end

-- Replaces the session folder's saved.lua with a fresh read of the WTF files, then reloads without writing the live
-- variables, so the import is a strict copy: what the addon changed since is discarded. req.wtf, when given, replaces
-- the paths the host opened with (the browser host lists the WTF folder again first); a host opened without WTF refuses
-- it too. Replies as reload does, plus warnings (a count); the files' own warnings go to the console.
function Host:reimport(req)
  local opts = self.sess.opts
  if not self.wtf then
    return { ok = false, error = "no WTF folder picked" }
  elseif not opts.sessionDir then
    return { ok = false, error = "no session folder" }
  elseif not validWtf(req.wtf) then
    return { ok = false, error = "malformed request: wtf must be { account?, character? } paths" }
  end
  self.wtf = req.wtf or self.wtf
  local warnings = Wtf.seed(opts, self.wtf)
  for _, warning in ipairs(warnings) do
    Console.push(self.sess.w, "system", warning)
  end
  local reply = self:reload({ keepSaved = true })
  reply.warnings = #warnings

  return reply
end

local function relay(self, method, req)
  local before = self.sess.seq
  local decorate = method == "snapshot" and function(reply)
    self:locate(reply)
  end or nil
  local text = self.sess:handle(method, req, decorate)
  if self.sess.seq ~= before then
    self:push("snapshot", { seq = self.sess.seq })
  end
  return text
end

local function dispatch(self, method, reqJson)
  if self.lost and method ~= "reload" and method ~= "reimport" then
    return Json.encode({ ok = false, error = self.lost })
  end
  local req, err = decode(reqJson)
  if not req then
    return Json.encode({ ok = false, error = err })
  end
  prepare(method, req)
  if method == "reload" then
    return Json.encode(self:reload(req))
  elseif method == "reimport" then
    return Json.encode(self:reimport(req))
  end
  local text = relay(self, method, req)
  local pending = self.sess.pendingReload
  if pending then
    self.sess.pendingReload = nil
    self:reload(pending)
  end
  return text
end

-- The JSON reply to a request; never raises. A /reload the call left pending runs right after it (dispatch). A lost
-- session (Host:reload) answers every request but a reload or a reimport (which reloads) with its error.
function Host:handleJson(method, reqJson)
  local ok, text = pcall(dispatch, self, method, reqJson)
  self:collectConsole()
  self:collectCombatLog()
  return ok and text or Json.encode({ ok = false, error = tostring(text) })
end

-- The events since the last drain as a JSON array of { event, data }; clears them.
function Host:drain()
  local text = Json.encode(self.outbox)
  self.outbox = {}
  return text
end

function Host:shutdown()
  self.sess:shutdown()
end

return M

-- SessionHost: what a host (the Python server, later the browser worker) keeps for the life of its process. It holds the
-- current Session across reloads, speaks JSON on the host boundary (handleJson in, drain out) and owns the outbox of
-- events the host publishes to viewers. The host only relays text; every rule about requests lives here.
local M = {}

local Assets = require("session_assets")
local Console = require("session_console")
local Json = require("json")
local Session = require("session")

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

-- opts: Session.new's. Starts the session; the outbox starts with the console lines the login printed.
function M.new(opts)
  local sess = Session.new(opts)
  local root = opts.addonDir:gsub("\\", "/"):gsub("/+$", "")
  local host = { sess = sess, outbox = {}, located = {}, consoleSeq = 0, addonRoots = { [sess.folder:lower()] = root } }
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

-- The one place a session is swapped; req is checked by Session.reload (SessionOptions.reopen). Replies { ok = true,
-- loads, flavor, screen = { width, height } }, or { ok = false, error } with the session kept. The new session carries
-- the console ring, so consoleSeq stays and only lines newer than it are queued.
function Host:reload(req)
  local ok, fresh = pcall(Session.reload, self.sess, req)
  if not ok then
    return { ok = false, error = tostring(fresh) }
  end
  self:collectConsole()
  self.sess, self.located = fresh, {}
  self:push("reload", { loads = fresh.loads })
  self:push("snapshot", { seq = fresh.seq })
  local screen = { width = fresh.w.screen.width, height = fresh.w.screen.height }
  return { ok = true, loads = fresh.loads, flavor = fresh.w.flavor, screen = screen }
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
  local req, err = decode(reqJson)
  if not req then
    return Json.encode({ ok = false, error = err })
  end
  prepare(method, req)
  if method == "reload" then
    return Json.encode(self:reload(req))
  end
  local text = relay(self, method, req)
  local pending = self.sess.pendingReload
  if pending then
    self.sess.pendingReload = nil
    local reply = self:reload(pending)
    if not reply.ok then
      Console.push(self.sess.w, "system", "Reload failed: " .. reply.error)
    end
  end
  return text
end

-- The JSON reply to a request; never raises. A /reload the call left pending runs right after it (dispatch).
function Host:handleJson(method, reqJson)
  local ok, text = pcall(dispatch, self, method, reqJson)
  self:collectConsole()
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

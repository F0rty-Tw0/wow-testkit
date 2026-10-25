-- SessionHost: what a host (the Python server, later the browser worker) keeps for the life of its process. It holds the
-- current Session across reloads, speaks JSON on the host boundary (handleJson in, drain out) and owns the outbox of
-- events the host publishes to viewers. The host only relays text; every rule about requests lives here.
local M = {}

local Assets = require("session_assets")
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

-- opts: Session.new's. Starts the session; the outbox starts empty.
function M.new(opts)
  local sess = Session.new(opts)
  local root = opts.addonDir:gsub("\\", "/"):gsub("/+$", "")
  return setmetatable({ sess = sess, outbox = {}, located = {}, addonRoots = { [sess.folder:lower()] = root } }, Host)
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

-- The one place a session is swapped. Replies { ok = true, loads }, or { ok = false, error } with the session kept.
function Host:reload(req)
  local ok, fresh = pcall(Session.reload, self.sess, req)
  if not ok then
    return { ok = false, error = tostring(fresh) }
  end
  self.sess, self.located = fresh, {}
  self:push("reload", { loads = fresh.loads })
  self:push("snapshot", { seq = fresh.seq })
  return { ok = true, loads = fresh.loads }
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
  return relay(self, method, req)
end

-- The JSON reply to a request; never raises.
function Host:handleJson(method, reqJson)
  local ok, text = pcall(dispatch, self, method, reqJson)
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

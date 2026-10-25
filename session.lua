-- Session: one addon logged into one flavor's world and kept alive, driven by wire requests (input, fire, slash, state)
-- and read as render snapshots, inspector views (tree, frame), console lines and the event list. call() answers with a
-- table, handle() with JSON; neither raises, so a bad request never ends the session. Only the holder swaps sessions
-- (Session.reload, or a /reload the slash method leaves in sess.pendingReload); session_host.lua is that holder.
local M = {}

local Client = require("client")
local Flavors = require("tools.flavors")
local Json = require("json")
local Render = require("render")
local Scenario = require("scenario")
local Screen = require("ui.screen")
local SessionConsole = require("session_console")
local SessionInput = require("session_input")
local SessionSaved = require("session_saved")
local SessionSlash = require("session_slash")
local SessionState = require("session_state")
local SessionView = require("session_view")
local Toc = require("toc")

local unpack = unpack
-- Localized: addon code may assign a global named debug.
local debugTraceback = debug.traceback

local DEFAULT_FLAVOR = "retail" -- "auto" means this until the flavor is detected from the TOC (Task 5.7)
-- The options a reload may change; the rest (addon folder, extract, session folder) belong to the process that started it.
local REOPENABLE = { flavor = true, screen = true }

local Session = {}
Session.__index = Session

local function copyList(list)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = v
  end
  return out
end

local function folderName(root)
  return root:gsub("\\", "/"):match("([^/]+)/*$") or root
end

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

-- Logs the addon in (reloading: the way the client does after /reload). A skipped addon (not declared on the flavor, no
-- TOC for it) records why in sess.skipped; any other failure is recorded in the world, so the snapshot lists it.
-- Nothing raises.
local function login(sess, reloading)
  local traceback
  local ok, err = xpcall(function()
    sess.s:login({ reloading = reloading })
  end, function(e)
    traceback = debugTraceback()
    return e
  end)
  if ok then
    return
  end
  local info = sess.s.info
  if info and info.status == "skipped" then
    sess.skipped = info.reason
  else
    sess.w:recordError(tostring(err), traceback)
  end
end

-- The session block of a snapshot.
local function infoOf(sess)
  local w = sess.w
  return {
    addon = sess.addon,
    flavor = w.flavor,
    flavors = copyList(Flavors.list),
    screen = { width = w.screen.width, height = w.screen.height },
    seq = sess.seq,
    loads = sess.loads,
    skipped = sess.skipped,
  }
end

-- { name, type, nilable } per payload parameter of a manifest event; type is the parameter's Lua type.
local function payloadOf(event)
  local out = {}
  for i, param in ipairs(event.payload or {}) do
    out[i] = { name = param.name, type = param.lua, nilable = param.nilable }
  end
  return out
end

-- Builds the world and logs the addon in, with the saved variables sessionDir holds. A session that follows `prior` (a
-- reload) continues its console and logs in as a reloading UI.
local function open(opts, prior)
  local flavor = opts.flavor
  if flavor == nil or flavor == "auto" then
    flavor = DEFAULT_FLAVOR
  end
  local root = opts.addonDir
  local name, nameErr = Toc.addonName(root)
  local extract = opts.extract and Client.load(opts.extract, flavor)
  local saved, warning
  if opts.sessionDir then
    saved, warning = SessionSaved.read(opts.sessionDir)
  end
  local s = Scenario.new({ addon = name, root = root, flavor = flavor, screen = opts.screen, client = extract, saved = saved })
  local folder = folderName(root)
  local sess = setmetatable({ opts = opts, s = s, w = s.w, folder = folder, addon = name or folder, seq = 0, loads = 1 }, Session)
  SessionConsole.install(sess.w, sess)
  if prior then
    SessionConsole.carry(sess.w, prior.console)
  end
  if warning then
    SessionConsole.push(sess.w, "system", "saved variables ignored: " .. warning)
  end
  SessionState.install(sess.w, sess)
  if opts.state then
    SessionState.apply(sess, opts.state)
  end
  if name then
    login(sess, prior ~= nil)
  else
    sess.w:recordError(nameErr)
  end
  return sess
end

-- opts: { addonDir, flavor? = "auto", screen?, sessionDir?, bindingsFile?, extract?, state? } (extract is a directory of
-- tools/client's output; sessionDir holds saved.lua). Raises only when no world can be built (an unknown flavor,
-- another world still active).
function M.new(opts)
  return open(opts, nil)
end

-- A new session over the same options (plus over's flavor and screen) and the same mock state, counting one more load.
-- The old one logs out first and, unless over.keepSaved, writes its saved variables; keepSaved loads what saved.lua
-- already holds. An option the world would refuse raises before sess is shut down, so the old session stays whole. seq
-- keeps counting, so a viewer never sees it go back.
function M.reload(sess, over)
  over = over or {}
  if over.keepSaved ~= nil and type(over.keepSaved) ~= "boolean" then
    error("reload: keepSaved must be true or false", 0)
  end
  local opts = {}
  for key, value in pairs(sess.opts) do
    opts[key] = value
  end
  for key, value in pairs(over) do
    if REOPENABLE[key] then
      opts[key] = value
    end
  end
  if opts.flavor ~= nil and opts.flavor ~= "auto" then
    Flavors.get(opts.flavor)
  end
  Screen.normalize(opts.screen)
  opts.state = sess.state
  sess:close(over.keepSaved)
  local fresh = open(opts, sess)
  fresh.loads, fresh.seq = sess.loads + 1, sess.seq + 1
  return fresh
end

-- Logs out the way the client does (PLAYER_LOGOUT), writes the saved variables unless keepSaved, and destroys the
-- world. A second call does nothing.
function Session:close(keepSaved)
  if self.closed then
    return
  end
  self.closed = true
  local ok, err = pcall(self.s.fireIfKnown, self.s, "PLAYER_LOGOUT")
  if not ok then
    SessionConsole.push(self.w, "error", "PLAYER_LOGOUT: " .. tostring(err))
  end
  if not keepSaved then
    SessionSaved.store(self)
  end
  self.w:destroy()
end

function Session:shutdown()
  self:close(false)
end

-- Each method returns its reply and whether it changed the world (call bumps seq then).
local METHODS = {
  snapshot = function(sess)
    local snapshot = Render.snapshot(sess.w)
    snapshot.session = infoOf(sess)
    return snapshot, false
  end,
  info = function(sess)
    local info = infoOf(sess)
    info.ok = true
    return info, false
  end,
  input = SessionInput.dispatch,
  fire = function(sess, req)
    if type(req.event) ~= "string" then
      error("fire: event must be a string", 0)
    end
    if req.args ~= nil and type(req.args) ~= "table" then
      error("fire: args must be a list", 0)
    end
    local args = req.args or {}
    sess.s:fire(req.event, unpack(args, 1, req.n or #args))
    return { ok = true }, true
  end,
  slash = function(sess, req)
    if type(req.text) ~= "string" then
      error("slash: text must be a string", 0)
    end
    local handled = sess.s:slash(req.text) or SessionSlash.run(sess, req.text)
    return { ok = true, handled = handled }, true
  end,
  -- An empty patch only reads the state, so it changes nothing.
  state = function(sess, req)
    return { ok = true, state = SessionState.apply(sess, req) }, next(req) ~= nil
  end,
  console = function(sess, req)
    return { ok = true, lines = SessionConsole.since(sess.w, tonumber(req.since) or 0) }, false
  end,
  -- Every event of the flavor's API docs with its payload parameters (type is the Lua type), sorted by name.
  events = function(sess)
    local events = sess.w.manifest.events
    local list = {}
    for i, name in ipairs(sortedKeys(events)) do
      list[i] = { name = name, payload = payloadOf(events[name]) }
    end
    return { ok = true, events = list }, false
  end,
  tree = function(sess)
    local tree = SessionView.tree(sess.w)
    tree.ok = true
    return tree, false
  end,
  frame = function(sess, req)
    local props = SessionView.frame(sess.w, req.id)
    if not props then
      return { ok = false, error = "frame: no widget with id '" .. tostring(req.id) .. "'" }, false
    end
    return { ok = true, props = props }, false
  end,
}

-- The reply table for method: { ok = false, error } for an unknown method, a malformed request or a raise.
function Session:call(method, req)
  local run = METHODS[method]
  if not run then
    return { ok = false, error = "unknown method '" .. tostring(method) .. "'" }
  end
  if type(req) ~= "table" then
    req = {}
  end
  local ok, reply, changed = pcall(run, self, req)
  if not ok then
    return { ok = false, error = tostring(reply) }
  end
  if changed then
    self.seq = self.seq + 1
  end
  return reply
end

-- call() as JSON. decorate(reply), when given, edits the reply table before it is encoded (the host adds the located
-- field of snapshot assets). An error anywhere becomes { ok = false, error }.
function Session:handle(method, req, decorate)
  local reply = self:call(method, req)
  if decorate then
    local ok, err = pcall(decorate, reply)
    if not ok then
      reply = { ok = false, error = tostring(err) }
    end
  end
  local ok, text = pcall(Json.encode, reply)
  return ok and text or Json.encode({ ok = false, error = tostring(text) })
end

return M

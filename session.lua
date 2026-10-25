-- Session: one addon logged into one flavor's world and kept alive, driven by wire requests (input, fire, slash, state)
-- and read as render snapshots and inspector views (tree, frame). call() answers with a table, handle() with JSON;
-- neither raises, so a bad request never ends the session. Only the holder swaps sessions (Session.reload);
-- session_host.lua is that holder.
local M = {}

local Client = require("client")
local Flavors = require("tools.flavors")
local Json = require("json")
local Render = require("render")
local Scenario = require("scenario")
local Screen = require("ui.screen")
local SessionInput = require("session_input")
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

-- Logs the addon in. A skipped addon (not declared on the flavor, no TOC for it) records why in sess.skipped; any
-- other failure is recorded in the world, so the snapshot lists it. Nothing raises.
local function login(sess)
  local traceback
  local ok, err = xpcall(function()
    sess.s:login()
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

-- State: units = { [token] = fixture } and mouseover = token, the way a scenario's s:unit and w:mouseover set them.
local function applyState(w, req)
  if req.units ~= nil then
    if type(req.units) ~= "table" then
      error("state: units must be an object of unit fixtures", 0)
    end
    for _, token in ipairs(sortedKeys(req.units)) do
      w:unit(token, req.units[token])
    end
  end
  if req.mouseover ~= nil then
    if type(req.mouseover) ~= "string" then
      error("state: mouseover must be a unit token", 0)
    end
    w:mouseover(req.mouseover)
  end
end

-- opts: { addonDir, flavor? = "auto", screen?, sessionDir?, bindingsFile?, extract?, state? } (extract is a directory of
-- tools/client's output). Builds the world and logs the addon in; raises only when no world can be built (an unknown
-- flavor, another world still active).
function M.new(opts)
  local flavor = opts.flavor
  if flavor == nil or flavor == "auto" then
    flavor = DEFAULT_FLAVOR
  end
  local root = opts.addonDir
  local name, nameErr = Toc.addonName(root)
  local extract = opts.extract and Client.load(opts.extract, flavor)
  local s = Scenario.new({ addon = name, root = root, flavor = flavor, screen = opts.screen, client = extract })
  local folder = folderName(root)
  local sess = setmetatable({ opts = opts, s = s, w = s.w, folder = folder, addon = name or folder, seq = 0, loads = 1 }, Session)
  if opts.state then
    applyState(sess.w, opts.state)
  end
  if name then
    login(sess)
  else
    sess.w:recordError(nameErr)
  end
  return sess
end

-- A new session over the same options (plus over's flavor and screen), counting one more load. A flavor or screen the
-- world would refuse raises before sess is shut down, so the old session stays whole. seq keeps counting, so a viewer
-- never sees it go back.
function M.reload(sess, over)
  local opts = {}
  for key, value in pairs(sess.opts) do
    opts[key] = value
  end
  for key, value in pairs(over or {}) do
    if REOPENABLE[key] then
      opts[key] = value
    end
  end
  if opts.flavor ~= nil and opts.flavor ~= "auto" then
    Flavors.get(opts.flavor)
  end
  Screen.normalize(opts.screen)
  sess:shutdown()
  local fresh = M.new(opts)
  fresh.loads, fresh.seq = sess.loads + 1, sess.seq + 1
  return fresh
end

function Session:shutdown()
  self.w:destroy()
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
    return { ok = true, handled = sess.s:slash(req.text) }, true
  end,
  state = function(sess, req)
    applyState(sess.w, req)
    return { ok = true }, true
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

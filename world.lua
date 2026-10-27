-- One offline WoW world per process: installs a flavor's API stubs, enums, constants and build info into _G,
-- tracks the execution context (addon / blizzard / scenario), and restores _G exactly on destroy.
local M = {}

local Flavors = require("tools.flavors")
local Manifest = require("manifest")
local LuaApi = require("luaapi")
local Luaext = require("luaext")
local WorldApi = require("world_api")
local WorldEvents = require("world_events")
local WorldSnapshot = require("world_snapshot")
local Screen = require("ui.screen")

local unpack = unpack
-- Host functions new and destroy use, kept as upvalues: addon writes land raw in _G, so an addon that reassigns
-- one (setfenv = nil, debug = true) must not break destroy or the next world.
local pairs, ipairs, rawget, rawset, type, setmetatable = pairs, ipairs, rawget, rawset, type, setmetatable
-- Same for World:run's pack, which runs while addon globals are live.
local select = select
local getfenv, setfenv = getfenv, setfenv
local getRawMetatable, setRawMetatable = debug.getmetatable, debug.setmetatable

local World = {}
World.__index = World
for name, fn in pairs(WorldEvents.methods) do
  World[name] = fn
end

local CONTEXTS = { addon = true, blizzard = true, scenario = true }
local CONTEXT_LIST = "addon, blizzard, scenario"
local BUILD_DATE = "Oct 1 2026"

local active = nil

local function pack(...)
  return { n = select("#", ...), ... }
end

local shallowCopy = WorldSnapshot.shallowCopy

local function contains(list, item)
  for _, v in ipairs(list) do
    if v == item then
      return true
    end
  end
  return false
end

-- Writes tbl[key]; writes into host tables other than _G (string, math, ...) are recorded for destroy.
function World:rawWrite(tbl, key, value)
  if tbl ~= _G and not self.created[tbl] then
    self.restores[#self.restores + 1] = { tbl, key, rawget(tbl, key) }
  end
  rawset(tbl, key, value)
end

-- Returns the table holding a dotted name's last part and that part; create builds missing namespaces.
function World:parentOf(name, create)
  local tbl, last = _G, nil
  for part in name:gmatch("[^.]+") do
    if last then
      local child = rawget(tbl, last)
      if child == nil and create then
        child = {}
        self:rawWrite(tbl, last, child)
        self.created[child] = true
      end
      if type(child) ~= "table" then
        return nil
      end
      tbl = child
    end
    last = part
  end
  return tbl, last
end

function World:set(name, value)
  local tbl, key = self:parentOf(name, true)
  if not tbl then
    error("cannot install '" .. name .. "': a namespace on its path is not a table", 3)
  end
  self:rawWrite(tbl, key, value)
end

-- True when the host Lua already defines name (e.g. Forever's documented `require`): stubs never replace it.
function World:hostHas(name)
  local tbl, key = self:parentOf(name, false)
  return tbl ~= nil and not self.created[tbl] and rawget(tbl, key) ~= nil
end

function World:installStub(name, signature)
  if not self:hostHas(name) then
    self:set(name, WorldApi.wrap(self, name, signature, nil))
  end
end

local function buildInfo(row)
  local version, build = row.version:match("^(%d+%.%d+%.%d+)%.(%d+)$")
  return function()
    return version, build, BUILD_DATE, row.tocVersion
  end
end

local function installBase(w, row)
  for name in pairs(w.globals.api) do
    if not w.manifest.functions[name] then
      w:installStub(name, nil)
    end
  end
  for name, signature in pairs(w.manifest.functions) do
    -- A documented Lua extension the kit implements (string.trim) is left to LuaApi.install below.
    local luaImplemented = w.globals.lua[name] and LuaApi.implements(name)
    if not signature.secureOnly and not luaImplemented then
      w:installStub(name, signature)
    end
  end
  local enum, constants = {}, {}
  for name, values in pairs(w.manifest.enums) do
    enum[name] = shallowCopy(values)
  end
  for name, values in pairs(w.manifest.constants) do
    constants[name] = shallowCopy(values)
  end
  w:set("Enum", enum)
  w:set("Constants", constants)
  for name, id in pairs(Flavors.WOW_PROJECT) do
    w:set(name, id)
  end
  w:set("WOW_PROJECT_ID", row.projectId)
  w:install("GetBuildInfo", buildInfo(row))
  Luaext.install(w)
  LuaApi.install(w)
end

-- opts.flavor: one of Flavors.list. opts.screen: { width, height, useUiScale, uiScale }, see ui/screen.lua. opts.client:
-- a client extract (client.lua) whose data the framexml.fakes.client fake installs; nil leaves the kit's own values. Errors
-- while another world is still active.
function M.new(opts)
  local row = Flavors.get(opts.flavor)
  if active then
    error("another world is active; destroy it first", 2)
  end
  local manifest, globals = Manifest.load(row.name)
  local w = setmetatable({
    flavor = row.name,
    manifest = manifest,
    globals = globals,
    screen = Screen.normalize(opts.screen),
    client = opts.client,
    calls = {},
    unscripted = {},
    errors = {},
    dev = { loads = {}, widgets = {}, unscripted = {} },
    warnings = {},
    realType = type,
    stubs = {},
    stack = {},
    created = {},
    restores = {},
    snapshotMt = getRawMetatable(_G),
    stringMt = getRawMetatable(""),
    threadEnv = getfenv(0),
    snapshot = WorldSnapshot.snapshotGlobals(),
    libraries = WorldSnapshot.snapshotLibraries(),
  }, World)
  WorldEvents.reset(w)
  active = w
  local ok, err = pcall(installBase, w, row)
  if not ok then
    w:destroy()
    error(err, 0)
  end
  return w
end

-- Restores _G and the host library tables exactly as snapshotted (added keys removed, replaced values and _G's
-- metatable restored), the string metatable and the running thread's environment (getfenv(0)). That is the thread
-- destroy runs on: called from another coroutine than World.new's, it leaves World.new's thread as it is. This holds
-- for thread environments only; destroy restores no function's environment. Addon code changes neither a host
-- thread's environment nor a kit function's (addon_env.lua setfenv), so only host code that changes a thread's must
-- call destroy from that thread.
function World:destroy()
  if active ~= self then
    return
  end
  setfenv(0, self.threadEnv)
  for i = #self.restores, 1, -1 do
    local entry = self.restores[i]
    rawset(entry[1], entry[2], entry[3])
  end
  setRawMetatable("", self.stringMt)
  WorldSnapshot.restoreLibraries(self.libraries)
  setRawMetatable(_G, self.snapshotMt)
  for k in pairs(_G) do
    if self.snapshot[k] == nil then
      rawset(_G, k, nil)
    end
  end
  for k, v in pairs(self.snapshot) do
    rawset(_G, k, v)
  end
  -- After _G is back: other modules read their host globals at call time.
  WorldEvents.reset(self)
  active = nil
end

function World:passesGate(name, opts)
  local gate = opts and opts.gate or "none"
  if gate == "none" then
    return true
  elseif gate == "api" then
    return self.manifest.functions[name] ~= nil or self.globals.api[name] ~= nil
  elseif gate == "framexml" then
    return self.globals.framexml[name] ~= nil or contains(opts.flavors or Flavors.list, self.flavor)
  end
  error("unknown gate '" .. tostring(gate) .. "'; valid: api, framexml, none", 3)
end

-- Installs a kit value. API functions keep counting, validation and w:stub overrides. Returns false when gated out.
function World:install(name, value, opts)
  if not self:passesGate(name, opts) then
    return false
  end
  local signature = self.manifest.functions[name]
  if type(value) == "function" and (signature or self.globals.api[name]) then
    value = WorldApi.wrap(self, name, signature, value)
  end
  self:set(name, value)
  return true
end

-- Sets the global named name, dots included (a SavedVariables name is one global); install and set split dotted
-- names into namespaces.
function World:setGlobal(name, value)
  rawset(_G, name, value)
end

-- impl: function | { returns = {...} } | { byArgs = { ["arg1|arg2"] = {...} }, default = {...} }.
-- On retail a stub gets the value a secret argument hides, as a kit implementation does (row C16).
function World:stub(name, impl)
  if not (self.manifest.functions[name] or self.globals.api[name]) then
    error("cannot stub '" .. tostring(name) .. "': not a WoW API function on " .. self.flavor, 2)
  end
  self.stubs[name] = impl
end

-- Calls fn(...) with context pushed; pops it on return and on error (rethrowing the original error value).
function World:run(context, fn, ...)
  if not CONTEXTS[context] then
    error("unknown context '" .. tostring(context) .. "'; valid: " .. CONTEXT_LIST, 2)
  end
  local stack = self.stack
  stack[#stack + 1] = context
  local results = pack(pcall(fn, ...))
  stack[#stack] = nil
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2, results.n)
end

function World:context()
  return self.stack[#self.stack]
end

function World:callerIsAddon()
  return self.stack[#self.stack] == "addon"
end

return M

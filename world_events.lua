-- World clock and timers (world_timers.lua), script registry (shared with widgets), event bus and error recording.
-- Mixed into the World methods by world.lua; state lives on the world and is reset on destroy.
local M = {}

local WorldTimers = require("world_timers")

local unpack = unpack

local START_TIME = 1000.0
local ADDON_SOURCE_PATTERN = 'addon:[^:\r\n"%]]+'
local TRUNCATED_SOURCE_PATTERN = '%.%.%.([^:\r\n"%]]+):%d+:'
-- Localized: addon code may assign a global named debug.
local getinfo, debugTraceback = debug.getinfo, debug.traceback
local ADDON_CHUNK_PREFIX = "@addon:"

local methods = {}
M.methods = methods
for name, fn in pairs(WorldTimers.methods) do
  methods[name] = fn
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Passes err to the current error handler under "addon" context. Used as the xpcall message handler, so the
-- handler sees the erroring stack. A failing handler falls back to recordError with both messages.
function methods:reportError(err)
  local stack = self.stack
  local depth = #stack
  stack[depth + 1] = "addon"
  local ok, handlerErr = pcall(self.errorHandler, err)
  stack[depth + 1] = nil
  if not ok then
    self:recordError(tostring(err) .. "\nerror handler failed: " .. tostring(handlerErr), debugTraceback())
  end
end

-- Calls fn(...); an error goes to the error handler. Returns the packed xpcall results ({ n, ok, ... }).
function methods:try(fn, ...)
  local args = pack(...)
  return pack(xpcall(function()
    return fn(unpack(args, 1, args.n))
  end, function(err)
    self:reportError(err)
  end))
end

-- try() under "addon" context. Returns the packed result ({ n, ok, ... }).
function methods:callAsAddon(fn, ...)
  local stack = self.stack
  local depth = #stack
  stack[depth + 1] = "addon"
  local results = self:try(fn, ...)
  for i = #stack, depth + 1, -1 do
    stack[i] = nil
  end
  return results
end

function M.reset(w)
  w.errorHandler = function(message)
    w:recordError(message, debugTraceback())
  end
  w.now = START_TIME
  w.timers = {}
  w.timerSeq = 0
  w.scripts = setmetatable({}, { __mode = "k" })
  w.eventFrames = {}
  w.chunks = {}
end

-- Registers a full chunk name ("addon:Name/path.lua"), so recordError can resolve the "...tail" form Lua 5.1 gives
-- chunk names longer than LUA_IDSIZE.
function methods:registerChunk(name)
  self.chunks[name] = true
end

-- The one registered chunk name ending in tail; nil when none or several do.
local function resolveTail(chunks, tail)
  local found
  for name in pairs(chunks) do
    if name:sub(-#tail) == tail then
      if found then
        return nil
      end
      found = name
    end
  end
  return found
end

local function sourceIn(w, text)
  if not text then
    return nil
  end
  text = tostring(text)
  local source = text:match(ADDON_SOURCE_PATTERN)
  if source then
    return source
  end
  for tail in text:gmatch(TRUNCATED_SOURCE_PATTERN) do
    source = resolveTail(w.chunks, tail)
    if source then
      return source
    end
  end
  return nil
end

function methods:recordError(message, traceback)
  local source = sourceIn(self, message) or sourceIn(self, traceback)
  self.errors[#self.errors + 1] = { message = message, traceback = traceback, source = source }
end

-- Scripts -----------------------------------------------------------------------------------------------------

local function scriptEntry(w, obj, scriptName)
  local byName = w.scripts[obj]
  if not byName then
    byName = {}
    w.scripts[obj] = byName
  end
  local entry = byName[scriptName]
  if not entry then
    entry = { hooks = {} }
    byName[scriptName] = entry
  end
  return entry
end

-- F3 (assumed, wiki API_ScriptObject_HookScript): hooks "remain in place until replaced or cleared with SetScript".
function methods:setScript(obj, scriptName, fn)
  local entry = scriptEntry(self, obj, scriptName)
  entry.fn = fn
  entry.hooks = {}
end

-- F3 (assumed, wiki API_ScriptObject_HookScript): with no handler, a hook is the handler, as SetScript would set it.
function methods:hookScript(obj, scriptName, fn)
  local entry = scriptEntry(self, obj, scriptName)
  if entry.fn == nil then
    entry.fn = fn

    return
  end
  entry.hooks[#entry.hooks + 1] = fn
end

function methods:getScript(obj, scriptName)
  local byName = self.scripts[obj]
  return byName and byName[scriptName] and byName[scriptName].fn
end

-- The widget's intrinsic type's handler for scriptName (plan.intrinsicScripts, ui/widgets.lua), or nil.
local function intrinsicScript(w, obj, scriptName)
  local st = w.ui and w.ui.state[obj]
  local scripts = st and st.plan.intrinsicScripts
  return scripts and scripts[scriptName]
end

-- Runs the intrinsic handler (kit code, fn(w, obj, st, ...), not replaceable), then the script and its hooks in
-- order, each receiving (obj, ...); errors in addon code are recorded, not raised.
function methods:callScript(obj, scriptName, ...)
  local intrinsic = intrinsicScript(self, obj, scriptName)
  if intrinsic then
    intrinsic(self, obj, self.ui.state[obj], ...)
  end
  local byName = self.scripts[obj]
  local entry = byName and byName[scriptName]
  if not entry then
    return
  end
  if entry.fn then
    self:callAsAddon(entry.fn, obj, ...)
  end
  for _, hook in ipairs(entry.hooks) do
    self:callAsAddon(hook, obj, ...)
  end
end

-- Events ------------------------------------------------------------------------------------------------------

-- The level, as error() in the caller counts it, of the nearest addon chunk on the stack; fallback when no addon
-- code is on it. Widget methods reach the kit through tail calls, so a fixed level can land on a lost frame.
local function addonLevel(fallback)
  local level = 3
  while true do
    local info = getinfo(level, "S")
    if not info then
      return fallback
    end
    if info.source:sub(1, #ADDON_CHUNK_PREFIX) == ADDON_CHUNK_PREFIX then
      return level - 1
    end
    level = level + 1
  end
end

local function checkEvent(w, event)
  if not (w.manifest.events[event] or w.globals.events[event]) then
    error("unknown event '" .. tostring(event) .. "' on " .. w.flavor, addonLevel(3))
  end
end

local function indexOf(list, item)
  for i, v in ipairs(list) do
    if v == item then
      return i
    end
  end
  return nil
end

function methods:registerEvent(frame, event)
  checkEvent(self, event)
  local frames = self.eventFrames[event] or {}
  self.eventFrames[event] = frames
  if not indexOf(frames, frame) then
    frames[#frames + 1] = frame
  end
end

function methods:unregisterEvent(frame, event)
  local frames = self.eventFrames[event]
  local i = frames and indexOf(frames, frame)
  if i then
    table.remove(frames, i)
  end
end

function methods:isEventRegistered(frame, event)
  local frames = self.eventFrames[event]
  return (frames and indexOf(frames, frame)) ~= nil
end

local function requiredCount(payload)
  for i = #payload, 1, -1 do
    if not payload[i].nilable then
      return i
    end
  end
  return 0
end

-- Warns on too many payload values, or too few: trailing nilable values may be omitted.
local function checkPayload(w, event, count)
  local spec = w.manifest.events[event]
  local payload = spec and spec.payload
  if payload and (count > #payload or count < requiredCount(payload)) then
    local message = "event %s fired with %d payload values; the %s manifest lists %d (%d required)"
    w.warnings[#w.warnings + 1] = string.format(message, event, count, w.flavor, #payload, requiredCount(payload))
  end
end

-- Dispatches OnEvent to frames registered when the fire began; frames unregistered meanwhile are skipped.
function methods:fire(event, ...)
  checkEvent(self, event)
  checkPayload(self, event, select("#", ...))
  local frames = self.eventFrames[event]
  if not frames then
    return
  end
  local snapshot = { unpack(frames) }
  for _, frame in ipairs(snapshot) do
    if indexOf(frames, frame) then
      self:callScript(frame, "OnEvent", event, ...)
    end
  end
end

return M

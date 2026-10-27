-- Taint tracking (Ruling R6). Execution taint is a stack (w.taint.stack) that World:run and World:callAsAddon push and pop:
-- an entry is the running addon's name, or false for secure execution. Slot taint (w.taint.slots[tbl][key] = addonName) is
-- recorded for writes through Taint.rawset (addon writes to _G, w:setGlobal, w:rawWrite) and, for the tables Taint.declare
-- names, found by comparing each with a shadow copy whenever a frame is pushed or popped. No proxy sits on _G or any table
-- addon code sees, so pairs, next, # and rawget behave as before. Every entry is logged to w.taint.log and its listeners.
local M = {}

-- Localized: addon code may assign globals of the same names.
local rawset, rawget, rawequal, pairs, ipairs, type, tostring = rawset, rawget, rawequal, pairs, ipairs, type, tostring
local setmetatable, pcall, error, select, unpack = setmetatable, pcall, error, select, unpack
local getinfo, tremove = debug.getinfo, table.remove

M.LOG_LIMIT = 1000

local ADDON_SOURCE = "^@addon:([^/\r\n]+)/"

-- Function -> owning addon name, or false for a function no addon chunk defined. A function's chunk never changes,
-- so the cache is shared by every world.
local ownerCache = setmetatable({}, { __mode = "k" })

local function weakKeys()
  return setmetatable({}, { __mode = "k" })
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- source: assumed (rows TS1, TS3, TS4) the stack, slot and declared-table model; the engine keeps taint in C.
function M.install(w)
  w.taint = { log = {}, stack = {}, slots = weakKeys(), declared = {}, lazy = {}, owners = weakKeys(), listeners = {}, seq = 0 }
  w.taint.write = function(tbl, key, value)
    M.rawset(w, tbl, key, value)
  end
  -- Lazy: a sweep on every push and pop would cost each addon callback a pass over their keys (Enum has ~1700); a
  -- smoke run past its budget hooks every call, so a 0-second ticker would pay that per key.
  M.declare(w, rawget(_G, "Enum"), "Enum", true)
  M.declare(w, rawget(_G, "Constants"), "Constants", true)
end

-- The running taint: the addon's name, or nil while execution is secure.
function M.current(w)
  local stack = w.taint.stack
  return stack[#stack] or nil
end

-- The addon whose chunk defined fn (or, for a wrapper Taint.adopt registered, the function it wraps); nil for kit code.
function M.ownerOf(w, fn)
  if type(fn) ~= "function" then
    return nil
  end
  local adopted = w.taint.owners[fn]
  if adopted then
    return adopted
  end
  local owner = ownerCache[fn]
  if owner == nil then
    owner = getinfo(fn, "S").source:match(ADDON_SOURCE) or false
    ownerCache[fn] = owner
  end
  return owner or nil
end

-- Makes wrapper report fn's owner; returns wrapper.
function M.adopt(w, wrapper, fn)
  w.taint.owners[wrapper] = M.ownerOf(w, fn)
  return wrapper
end

-- Appends entry to the log (seq and time filled in, the oldest dropped past LOG_LIMIT) and passes it to each listener.
function M.record(w, entry)
  local t = w.taint
  t.seq = t.seq + 1
  entry.seq, entry.time = t.seq, w.now
  local log = t.log
  log[#log + 1] = entry
  if #log > M.LOG_LIMIT then
    tremove(log, 1)
  end
  for _, listener in ipairs(t.listeners) do
    listener(entry)
  end
  return entry
end

-- Calls fn(entry) with each entry logged from now on.
function M.listen(w, fn)
  local listeners = w.taint.listeners
  listeners[#listeners + 1] = fn
end

-- The label a write to tbl is logged under ("global" for _G), or nil when tbl is neither _G nor declared.
local function labelOf(t, tbl)
  if tbl == _G then
    return "global"
  end
  for _, entry in ipairs(t.declared) do
    if entry.tbl == tbl then
      return entry.label
    end
  end
  return t.lazy[tbl]
end

local function slotsOf(t, tbl)
  local slots = t.slots[tbl]
  if not slots then
    slots = {}
    t.slots[tbl] = slots
  end
  return slots
end

-- Taints tbl[key] with taint (nil/false clears it). The first taint of a key that held a value is logged.
local function attribute(w, tbl, key, held, taint)
  local t = w.taint
  if not taint then
    local slots = t.slots[tbl]
    if slots then
      slots[key] = nil
    end
    return
  end
  local slots = slotsOf(t, tbl)
  local label = held and slots[key] == nil and labelOf(t, tbl)
  slots[key] = taint
  if label then
    local text = (label == "global" and "global " or label .. ".") .. tostring(key) .. " tainted by " .. taint
    M.record(w, { kind = "write", addon = taint, name = key, text = text })
  end
end

-- rawset(tbl, key, value), tainting the slot with the running taint (secure execution clears it). Host rawset raises
-- first, so a bad table or key errors as before and taints nothing.
function M.rawset(w, tbl, key, value)
  local held = type(tbl) == "table" and rawget(tbl, key) ~= nil
  rawset(tbl, key, value)
  attribute(w, tbl, key, held, M.current(w))
end

-- Starts sweeping tbl when it was declared lazy; its changes until now are not attributed.
local function wake(w, tbl)
  local label = w.taint.lazy[tbl]
  if label then
    w.taint.lazy[tbl] = nil
    M.declare(w, tbl, label)
  end
end

-- The addon that tainted tbl[key], or nil when the slot is secure.
function M.slotOf(w, tbl, key)
  wake(w, tbl)
  local slots = w.taint.slots[tbl]
  return slots and slots[key] or nil
end

-- Tracks tbl's fields under label: changes are found by Taint.sweep. A lazy table is swept only once Taint.slotOf or
-- Taint.read first asks about it. A table declared twice keeps its first label.
function M.declare(w, tbl, label, lazy)
  if type(tbl) ~= "table" or labelOf(w.taint, tbl) then
    return
  elseif lazy then
    w.taint.lazy[tbl] = label
    return
  end
  local shadow, count = {}, 0
  for k, v in pairs(tbl) do
    shadow[k], count = v, count + 1
  end
  local declared = w.taint.declared
  declared[#declared + 1] = { tbl = tbl, label = label, shadow = shadow, count = count }
end

local function sweepTable(w, entry, taint)
  local tbl, shadow = entry.tbl, entry.shadow
  local count, added = 0, 0
  for k, v in pairs(tbl) do
    count = count + 1
    local old = shadow[k]
    if not rawequal(old, v) then
      added = old == nil and added + 1 or added
      attribute(w, tbl, k, old ~= nil, taint)
      shadow[k] = v
    end
  end
  -- The shadow now holds every key of tbl plus the removed ones; a removal pass only when there are some.
  if entry.count + added ~= count then
    for k in pairs(shadow) do
      if rawget(tbl, k) == nil then
        attribute(w, tbl, k, true, taint)
        shadow[k] = nil
      end
    end
  end
  entry.count = count
end

-- Attributes every change to the declared tables since the last sweep (changed, added and removed keys) to popped, the
-- taint of the frame that made them; false or nil clears the slots.
function M.sweep(w, popped)
  for _, entry in ipairs(w.taint.declared) do
    sweepTable(w, entry, popped)
  end
end

-- Pushes a frame running fn: fn's owner, else (kit code, or no fn) the running taint. The declared tables are swept for
-- the frame below first, so this frame's pop sees only its own changes. Returns the mark Taint.pop takes.
function M.push(w, fn)
  local stack = w.taint.stack
  local mark = #stack
  M.sweep(w, stack[mark])
  stack[mark + 1] = M.ownerOf(w, fn) or stack[mark] or false
  return mark
end

-- Pops every frame above mark, then sweeps the declared tables for the innermost one.
function M.pop(w, mark)
  local stack = w.taint.stack
  local popped = stack[#stack]
  for i = #stack, mark + 1, -1 do
    stack[i] = nil
  end
  M.sweep(w, popped)
end

-- Calls fn(...) with a secure frame pushed; pops it on return and on error (rethrowing the original error value).
function M.secure(w, fn, ...)
  local mark = M.push(w, nil)
  w.taint.stack[mark + 1] = false
  local results = pack(pcall(fn, ...))
  M.pop(w, mark)
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2, results.n)
end

-- source: assumed (row TS4) reading a tainted slot taints the running frame; the kit applies it only where it calls this.
function M.read(w, tbl, key)
  local stack = w.taint.stack
  local depth = #stack
  local taint = M.slotOf(w, tbl, key)
  if depth == 0 or not taint or stack[depth] == taint then
    return
  end
  stack[depth] = taint
  local text = "execution tainted by " .. taint .. " reading " .. tostring(key)
  M.record(w, { kind = "read", addon = taint, name = key, text = text })
end

return M

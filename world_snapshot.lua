-- Copies of the host state a world changes, taken before it installs anything: _G's keys and the host library
-- tables. world.lua's destroy restores from them.
local M = {}

-- Host functions the snapshots use, kept as upvalues: addon writes land raw in _G, so an addon that reassigns one
-- (pairs = nil, debug = true) must not break destroy or the next world.
local pairs, ipairs, rawget, rawset, type = pairs, ipairs, rawget, rawset, type
local getRawMetatable = debug.getmetatable

-- Host library tables addon code (and the kit's LuaAPI installs) may write into; restored exactly on destroy.
local LIBRARIES = { "string", "table", "math", "os", "coroutine", "bit" }

local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end
M.shallowCopy = shallowCopy

-- { [library table] = shallow copy } for each library the host has, plus the string metatable (addon code reaches
-- it through getmetatable("")).
function M.snapshotLibraries()
  local snapshot = {}
  for _, name in ipairs(LIBRARIES) do
    local lib = rawget(_G, name)
    if type(lib) == "table" then
      snapshot[lib] = shallowCopy(lib)
    end
  end
  local stringMt = getRawMetatable("")
  if stringMt then
    snapshot[stringMt] = shallowCopy(stringMt)
  end
  return snapshot
end

function M.restoreLibraries(snapshot)
  for lib, saved in pairs(snapshot) do
    for k in pairs(lib) do
      if saved[k] == nil then
        rawset(lib, k, nil)
      end
    end
    for k, v in pairs(saved) do
      rawset(lib, k, v)
    end
  end
end

function M.snapshotGlobals()
  local snapshot = {}
  for k, v in pairs(_G) do
    snapshot[k] = v
  end
  return snapshot
end

return M

-- An addon's setmetatable(_G, ...): __index and __newindex handlers, misuse errors at the addon's line, and the
-- metatable gone on destroy.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local fs = require("fs")

local function errorMessages(w)
  local messages = {}
  for i, entry in ipairs(w.errors) do
    messages[i] = tostring(entry.message)
  end
  return table.concat(messages, "\n")
end

-- Writes a one-file retail addon named name whose Core.lua is source; returns its root.
local function tempAddon(name, source)
  local root = Tmp.dir("addon") .. "/" .. name
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. name .. ".toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  return root
end

local function loadSource(w, name, source)
  local ns = Addon.load(w, { name = name, root = tempAddon(name, source) })
  A.eq(errorMessages(w), "")
  return ns
end

local GLOBALS_INDEX = [[
local _, ns = ...
ns.before = getmetatable(_G)
local mt = { __index = function(_, key) return "missing:" .. key end }
ns.returned = setmetatable(_G, mt) == _G
ns.after = getmetatable(_G) == mt
ns.type = type(CreateFrame)
ns.uiParent = type(UIParent)
OwnGlobal = 1
ns.own = OwnGlobal
ns.missing = NoSuchGlobal
ns.missingViaG = _G.NoSuchGlobalViaG
]]

local function test_addon_globals_metatable_index_fires_only_for_absent_globals_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtIndex", GLOBALS_INDEX)
    A.eq(ns.before, nil)
    A.eq(ns.returned, true)
    A.eq(ns.after, true)
    A.same({ ns.type, ns.uiParent, ns.own }, { "function", "table", 1 })
    A.same({ ns.missing, ns.missingViaG }, { "missing:NoSuchGlobal", "missing:NoSuchGlobalViaG" })
    A.eq(rawget(_G, "OwnGlobal"), 1)
    A.eq(_G.NoSuchGlobal, nil)
  end)
end

local GLOBALS_NEWINDEX = [[
local _, ns = ...
ExistingGlobal = 1
ns.seen = {}
setmetatable(_G, { __newindex = function(t, key, value)
  ns.seen[#ns.seen + 1] = key
  rawset(t, key, value)
end })
ExistingGlobal = 2
NewGlobal = 3
]]

local function test_addon_globals_metatable_newindex_fires_only_for_new_globals_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtNewIndex", GLOBALS_NEWINDEX)
    A.same(ns.seen, { "NewGlobal" })
    A.same({ rawget(_G, "ExistingGlobal"), rawget(_G, "NewGlobal") }, { 2, 3 })
  end)
end

-- A cleared base-library name is absent from the view, so its next write is a new global the handler hears.
local CLEARED_NEWINDEX = [[
local _, ns = ...
type = nil
ns.seen = {}
setmetatable(_G, { __newindex = function(t, key, value)
  ns.seen[#ns.seen + 1] = key
  rawset(t, key, value)
end })
type = 5
tostring = 6
ns.type, ns.tostring = type, tostring
]]

local function test_addon_globals_metatable_newindex_fires_for_a_cleared_base_library_name_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtCleared", CLEARED_NEWINDEX)
    A.same({ ns.seen, ns.type, ns.tostring, type(rawget(_G, "type")) }, { { "type" }, 5, 6, "function" })
  end)
end

local function test_second_addon_sees_the_first_addons_globals_metatable_assumed()
  HF.withFrameXML("retail", function(w)
    loadSource(w, "MtFirst", 'SharedMt = { __index = function() return "first" end }\nsetmetatable(_G, SharedMt)\n')
    local ns = loadSource(w, "MtSecond", "local _, ns = ...\nns.same = getmetatable(_G) == SharedMt\nns.missing = Nope\n")
    A.same({ ns.same, ns.missing }, { true, "first" })
  end)
end

local function test_setmetatable_on_g_with_a_non_table_errors_at_the_callers_line()
  HF.withFrameXML("retail", function(w)
    Addon.load(w, { name = "MtBad", root = tempAddon("MtBad", "local x = 1\nsetmetatable(_G, 5)\n") })
    A.contains(errorMessages(w), "MtBad/Core.lua:2: bad argument #2 to 'setmetatable' (nil or table expected)")
  end)
end

local METATABLE_MISUSE = [[
local _, ns = ...
ns.a = select(2, pcall(function() local t = setmetatable({}, 5) return t end))
local locked = setmetatable({}, { __metatable = false })
ns.b = select(2, pcall(function() local t = setmetatable(locked, {}) return t end))
ns.c = select(2, pcall(function() local mt = getmetatable() return mt end))
ns.d = select(2, pcall(function() local t = setmetatable(5, {}) return t end))
ns.e = select(2, pcall(function() local t = setmetatable(_G) return t end))
ns.f = getmetatable(locked)
ns.g = select(2, pcall(function() local t = setmetatable() return t end))
]]

-- Runs source as a plain Lua chunk named like the addon's file, outside any sandbox; returns its ns.
local function plainRun(source, chunkName)
  local ns = {}
  assert(loadstring(source, "@" .. chunkName))(nil, ns)
  return ns
end

local function test_metatable_misuse_errors_like_plain_lua_at_the_addon_line()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtMisuse", METATABLE_MISUSE)
    local plain = plainRun(METATABLE_MISUSE, "addon:MtMisuse/Core.lua")
    A.eq(ns.a, "addon:MtMisuse/Core.lua:2: bad argument #2 to 'setmetatable' (nil or table expected)")
    for _, key in ipairs({ "a", "b", "c", "d", "e", "f", "g" }) do
      A.eq(ns[key], plain[key], key)
    end
  end)
end

-- Known gap: the overrides are Lua functions, so `return setmetatable(...)` is a real tail call that drops the
-- addon's frame, and the error has no location; plain Lua's C setmetatable keeps it.
local function test_tail_called_setmetatable_misuse_has_no_location()
  HF.withFrameXML("retail", function(w)
    local source = "local _, ns = ...\nns.a = select(2, pcall(function() return setmetatable({}, 5) end))\n"
    local ns = loadSource(w, "MtTail", source)
    A.eq(ns.a, "bad argument #2 to 'setmetatable' (nil or table expected)")
    A.eq(plainRun(source, "addon:MtTail/Core.lua").a, "addon:MtTail/Core.lua:2: " .. ns.a)
  end)
end

local GLOBALS_PROTECTED = [[
local _, ns = ...
setmetatable(_G, { __metatable = "locked", __index = function() return "x" end })
ns.mt = getmetatable(_G)
ns.err = select(2, pcall(function() local t = setmetatable(_G, nil) return t end))
ns.still = Nope
]]

local function test_protected_globals_metatable_is_hidden_and_kept()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtLocked", GLOBALS_PROTECTED)
    A.same({ ns.mt, ns.err, ns.still }, { "locked", "addon:MtLocked/Core.lua:4: cannot change a protected metatable", "x" })
  end)
end

local STRICT_GLOBALS = [[
local _, ns = ...
local TAG = {}
local mt = {
  __index = function(_, k)
    if k == "LevelOne" then error("level one " .. k) end
    if k == "Arith" then local n = nil return n + 1 end
    if k == "Tagged" then error(TAG) end
    if k == "Nested" then return UndeclaredInner end
    error("read of undeclared global " .. k, 2)
  end,
  __newindex = function(_, k) error("write of undeclared global " .. k, 2) end,
}
setmetatable(_G, mt)
ns.read = select(2, pcall(function() local x = UndeclaredRead return x end))
ns.write = select(2, pcall(function() UndeclaredWrite = 1 end))
ns.viaG = select(2, pcall(function() local x = _G.UndeclaredViaG return x end))
ns.own = select(2, pcall(function() local x = mt.__index(nil, "Direct") return x end))
ns.levelOne = select(2, pcall(function() local x = LevelOne return x end))
ns.arith = select(2, pcall(function() local x = Arith return x end))
ns.tagged = select(2, pcall(function() local x = Tagged return x end)) == TAG
ns.nested = select(2, pcall(function() local x = Nested return x end))
ns.gsub = select(2, pcall(function() local s = string.gsub("abc", "%w+", _G) return s end))
setmetatable(_G, nil)
]]

-- STRICT_GLOBALS as a plain chunk whose globals table is a fresh one holding only what it calls.
local function plainStrict(chunkName)
  local env = { setmetatable = setmetatable, select = select, pcall = pcall, error = error, string = string }
  env._G = env
  local ns = {}
  setfenv(assert(loadstring(STRICT_GLOBALS, "@" .. chunkName)), env)(nil, ns)
  return ns
end

local function test_globals_handler_errors_name_the_addon_line_like_plain_lua()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtStrict", STRICT_GLOBALS)
    local plain = plainStrict("addon:MtStrict/Core.lua")
    A.eq(ns.read, "addon:MtStrict/Core.lua:14: read of undeclared global UndeclaredRead")
    A.same({ ns.tagged, ns.gsub }, { true, "read of undeclared global abc" })
    for _, key in ipairs({ "read", "write", "viaG", "own", "levelOne", "arith", "tagged", "nested", "gsub" }) do
      A.eq(ns[key], plain[key], key)
    end
  end)
end

local HANDLER_SEES_VIEW = [[
local _, ns = ...
setmetatable(_G, { __index = function(t)
  ns.isG = t == _G
  ns.rawDebug = rawget(t, "debug")
end })
local x = Missing
]]

local function test_globals_index_handler_gets_the_addons_g_not_the_real_one_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtView", HANDLER_SEES_VIEW)
    A.same({ ns.isG, ns.rawDebug }, { true, nil })
  end)
end

local TABLE_HANDLERS = [[
local _, ns = ...
local sink = {}
setmetatable(_G, { __index = { Fallback = 1 }, __newindex = sink })
ns.fallback, ns.fallbackViaG = Fallback, _G.Fallback
NewOne = 2
ns.sunk, ns.raw = sink.NewOne, rawget(_G, "NewOne")
]]

local function test_table_valued_globals_handlers_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtTables", TABLE_HANDLERS)
    A.same({ ns.fallback, ns.fallbackViaG, ns.sunk, ns.raw }, { 1, 1, 2, nil })
    A.eq(rawget(_G, "NewOne"), nil)
  end)
end

local CLEARED = [[
local _, ns = ...
setmetatable(_G, { __index = function() return "x" end })
ns.returned = setmetatable(_G, nil) == _G
ns.mt, ns.missing = getmetatable(_G), Nope
]]

local function test_setmetatable_g_nil_clears_the_globals_metatable_assumed()
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtCleared", CLEARED)
    A.same({ ns.returned, ns.mt, ns.missing }, { true, nil, nil })
  end)
end

local HIDDEN_NEWINDEX = [[
local _, ns = ...
ns.seen = {}
setmetatable(_G, { __newindex = function(t, k)
  ns.seen[#ns.seen + 1] = k
  ns.isG, ns.rawDebug = t == _G, rawget(t, "debug")
end })
io = 1
SomeNew = 2
]]

local function test_globals_newindex_fires_for_a_host_only_name_assumed()
  local hostIo = io
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtHidden", HIDDEN_NEWINDEX)
    A.same(ns.seen, { "io", "SomeNew" })
    A.same({ ns.isG, ns.rawDebug }, { true, nil })
    A.eq(rawget(_G, "io"), hostIo)
  end)
end

local function test_globals_metatable_is_gone_after_destroy()
  local hostMt = debug.getmetatable(_G)
  HF.withFrameXML("retail", function(w)
    loadSource(w, "MtGone", 'setmetatable(_G, { __index = function() return "x" end })\n')
  end)
  A.eq(debug.getmetatable(_G), hostMt)
  HF.withFrameXML("retail", function(w)
    local ns = loadSource(w, "MtFresh", "local _, ns = ...\nns.mt = getmetatable(_G)\nns.missing = Nope\n")
    A.same({ ns.mt, ns.missing }, { nil, nil })
  end)
end

return function()
  test_addon_globals_metatable_index_fires_only_for_absent_globals_assumed()
  test_addon_globals_metatable_newindex_fires_only_for_new_globals_assumed()
  test_addon_globals_metatable_newindex_fires_for_a_cleared_base_library_name_assumed()
  test_second_addon_sees_the_first_addons_globals_metatable_assumed()
  test_setmetatable_on_g_with_a_non_table_errors_at_the_callers_line()
  test_metatable_misuse_errors_like_plain_lua_at_the_addon_line()
  test_tail_called_setmetatable_misuse_has_no_location()
  test_protected_globals_metatable_is_hidden_and_kept()
  test_globals_handler_errors_name_the_addon_line_like_plain_lua()
  test_globals_index_handler_gets_the_addons_g_not_the_real_one_assumed()
  test_table_valued_globals_handlers_assumed()
  test_setmetatable_g_nil_clears_the_globals_metatable_assumed()
  test_globals_newindex_fires_for_a_host_only_name_assumed()
  test_globals_metatable_is_gone_after_destroy()
end

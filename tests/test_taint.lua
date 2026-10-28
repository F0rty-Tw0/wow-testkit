-- Taint tracking core (Ruling R6): execution taint per addon entry, slot taint on _G and declared tables, reads that
-- taint the execution, the log and its listeners. Lua 5.1 only.
local A = require("assert")
local Callsite = require("ui.callsite")
local CombatH = require("tests.helpers.combat")
local H = require("tests.helpers.taint")
local Secret = require("combat_secret")

local function test_addon_chunk_taints_the_execution_with_its_addon_name_assumed() -- TS1
  H.withTaint("retail", function(w, Taint)
    H.probe(w, Taint)
    A.eq(Taint.current(w), nil)
    local r = H.run(w, "Foo", "seen = TK_Seen()")
    A.truthy(r[1])
    A.eq(_G.seen, "Foo")
    A.eq(Taint.current(w), nil) -- restored on return
  end)
end

local function test_addon_global_overwrite_taints_the_slot_and_logs_once_assumed() -- TS3
  H.withTaint("retail", function(w, Taint)
    H.run(w, "Foo", "UnitName = function() return 'x' end; FooDB = {}")
    A.eq(Taint.slotOf(w, _G, "UnitName"), "Foo")
    A.eq(Taint.slotOf(w, _G, "FooDB"), "Foo")
    A.eq(#w.taint.log, 1) -- FooDB is new: tainted, not logged
    A.eq(w.taint.log[1].text, "global UnitName tainted by Foo")
    w:setGlobal("UnitName", function() end) -- secure write
    A.eq(Taint.slotOf(w, _G, "UnitName"), nil)
  end)
end

local function test_declared_table_fields_are_attributed_without_a_proxy() -- R6
  H.withTaint("retail", function(w, Taint)
    local globalsMt = debug.getmetatable(_G) -- the frames fake's lazy global frames (framexml/fakes/frames.lua)
    local t = { keep = 1 }
    w:setGlobal("KitT", t)
    Taint.declare(w, t, "Kit")
    H.run(w, "Foo", "KitT.a = 1; KitT.keep = nil")
    A.same({ Taint.slotOf(w, t, "a"), Taint.slotOf(w, t, "keep") }, { "Foo", "Foo" })
    A.eq(w.taint.log[1].text, "Kit.keep tainted by Foo")
    A.eq(getmetatable(t), nil)
    A.eq(t.a, 1)
    w:run("blizzard", function()
      t.a = 2
    end) -- a secure change clears the slot at the next sweep
    A.eq(Taint.slotOf(w, t, "a"), nil)
    A.eq(debug.getmetatable(_G), globalsMt)
  end)
end

-- Enum (and Constants) are swept only from the first query on; a change before it is not attributed (known gap).
local function test_a_table_declared_with_keys_tracks_only_those_keys() -- R6
  H.withTaint("retail", function(w, Taint)
    local t = { watched = 1, other = 1 }
    w:setGlobal("KitK", t)
    Taint.declare(w, t, "KitK", false, { "watched" })
    H.run(w, "Foo", "KitK.watched = 2; KitK.other = 2")
    A.same({ Taint.slotOf(w, t, "watched"), Taint.slotOf(w, t, "other") }, { "Foo", nil })
    A.eq(w.taint.log[#w.taint.log].text, "KitK.watched tainted by Foo")
  end)
end

local function test_enum_is_declared_lazily_from_the_first_query()
  H.withTaint("retail", function(w, Taint)
    local before = next(_G.Enum)
    local after = next(_G.Enum, before)
    H.run(w, "Foo", "Enum." .. before .. " = {}")
    A.eq(Taint.slotOf(w, _G.Enum, before), nil)
    H.run(w, "Foo", "Enum." .. after .. " = {}")
    A.eq(Taint.slotOf(w, _G.Enum, after), "Foo")
    A.eq(w.taint.log[#w.taint.log].text, "Enum." .. after .. " tainted by Foo")
  end)
end

local function test_reading_a_tainted_slot_taints_the_running_execution_assumed() -- TS4
  H.withTaint("retail", function(w, Taint)
    H.run(w, "Foo", "UnitName = function() end")
    local seen
    w:run("blizzard", function()
      Taint.read(w, _G, "UnitName")
      seen = Taint.current(w)
    end)
    A.eq(seen, "Foo")
    A.eq(Taint.current(w), nil)
    A.eq(w.taint.log[#w.taint.log].kind, "read")
  end)
end

local function test_kit_function_inherits_the_running_taint()
  H.withTaint("retail", function(w, Taint)
    local seen = {}
    local function kit()
      seen[#seen + 1] = Taint.current(w) or "secure"
    end
    w:setGlobal("TK_Call", function()
      w:callAsAddon(kit)
    end)
    w:callAsAddon(kit)
    H.run(w, "Foo", "TK_Call()")
    A.same(seen, { "secure", "Foo" })
  end)
end

local function test_taint_is_restored_after_an_error()
  H.withTaint("retail", function(w, Taint)
    local r = H.run(w, "Foo", "error('boom')")
    A.eq(r[1], false)
    A.eq(Taint.current(w), nil)
    A.eq(#w.taint.stack, 0)
    A.contains(w.errors[#w.errors].message, "boom")
  end)
end

local function test_rawset_on_the_addon_view_taints_the_slot()
  H.withTaint("retail", function(w, Taint)
    H.run(w, "Foo", 'rawset(_G, "X1", 1)')
    A.eq(_G.X1, 1)
    A.eq(Taint.slotOf(w, _G, "X1"), "Foo")
  end)
end

local function test_timer_after_callback_keeps_the_scheduling_owner()
  H.withTaint("retail", function(w, Taint)
    H.probe(w, Taint)
    H.run(w, "Foo", "C_Timer.After(1, function() later = TK_Seen() end)")
    w:advance(1)
    A.eq(_G.later, "Foo")
  end)
end

local function test_a_loadstring_chunk_runs_with_its_builder_taint_assumed() -- TS1
  H.withTaint("retail", function(w, Taint)
    local cast = 0
    w:stub("CastSpellByName", function()
      cast = cast + 1
    end)
    local src = [[
      C_Timer.After(0, loadstring("TK_L = issecure(); CastSpellByName('Fireball')"))
      local f = CreateFrame("Frame")
      f:SetScript("OnEvent", loadstring("TK_E = issecure(); CastSpellByName('Fireball')"))
      f:RegisterEvent("PLAYER_ENTERING_WORLD")
    ]]
    H.run(w, "Foo", src)
    w:advance(0.1)
    w:fire("PLAYER_ENTERING_WORLD")
    local blocked = H.events(w, "blocked")
    local owners = { blocked[1] and blocked[1].addon, blocked[2] and blocked[2].addon }
    A.same({ _G.TK_L, _G.TK_E, cast, #blocked, owners }, { false, false, 0, 2, { "Foo", "Foo" } })
    local load = H.chunk(w, "Foo", "return loadstring")()
    local secureBuilt = w:run("blizzard", load, "return 1")
    A.eq(Taint.ownerOf(w, secureBuilt), nil) -- a secure builder leaves the chunk unowned
    local forcedBuilt = w:run("blizzard", function()
      _G.forceinsecure()
      return load("return 1")
    end)
    A.eq(Taint.ownerOf(w, forcedBuilt), nil) -- forceinsecure is not an addon: a chunk built after it stays unowned
  end)
end

local function test_log_is_capped_and_listeners_hear_each_entry()
  H.withTaint("retail", function(w, Taint)
    local heard = 0
    Taint.listen(w, function()
      heard = heard + 1
    end)
    for i = 1, Taint.LOG_LIMIT + 1 do
      Taint.record(w, { kind = "forced", addon = "Foo", name = "n" .. i, text = "t" .. i })
    end
    A.eq(#w.taint.log, Taint.LOG_LIMIT)
    A.eq(w.taint.log[1].seq, 2)
    A.eq(heard, Taint.LOG_LIMIT + 1)
  end)
end

local function test_nested_frame_does_not_take_the_outer_frames_table_changes()
  H.withTaint("retail", function(w, Taint)
    local t = {}
    w:setGlobal("KitT", t)
    Taint.declare(w, t, "Kit")
    w:setGlobal("BarFn", H.chunk(w, "Bar", "KitT.b = 1"))
    w:setGlobal("TK_Call", function(fn)
      w:callAsAddon(fn)
    end)
    H.run(w, "Foo", "KitT.a = 1; TK_Call(BarFn)")
    A.same({ Taint.slotOf(w, t, "a"), Taint.slotOf(w, t, "b") }, { "Foo", "Bar" })
  end)
end

-- Taint does not decide who reads a secret: the context does (combat_secret_value.lua).
local function test_secret_args_still_follow_context_after_taint()
  CombatH.withCombat("retail", function(w, _, s)
    s:preset("dungeon", { inCombat = true })
    local Taint = require("taint")
    local guid = w:run("addon", _G.UnitGUID, "party1") -- addon context, secure execution
    A.eq(Taint.current(w), nil)
    A.eq(_G.issecretvalue(guid), true)
    w:setGlobal("TK_Blizzard", function()
      return w:run("blizzard", _G.UnitGUID, "party1")
    end)
    local r = H.run(w, "Foo", "return TK_Blizzard()") -- blizzard context, tainted by Foo
    A.eq(r[2], Secret.reveal(guid))
  end)
end

-- An error raised from taint.lua credits the first frame outside it (ui/callsite.lua isKit).
local function test_callsite_skips_taint_module_frames()
  local root = debug.getinfo(Callsite.level, "S").source:match("^@(.*)ui[/\\]callsite%.lua$")
  local function raiser()
    return Callsite.level()
  end
  local viaTaint = assert(loadstring("local f = ...; local level = f(); return level", "@" .. root .. "taint.lua"))
  A.eq(viaTaint(raiser), 3)
end

return function()
  test_addon_chunk_taints_the_execution_with_its_addon_name_assumed()
  test_addon_global_overwrite_taints_the_slot_and_logs_once_assumed()
  test_declared_table_fields_are_attributed_without_a_proxy()
  test_a_table_declared_with_keys_tracks_only_those_keys()
  test_enum_is_declared_lazily_from_the_first_query()
  test_reading_a_tainted_slot_taints_the_running_execution_assumed()
  test_kit_function_inherits_the_running_taint()
  test_taint_is_restored_after_an_error()
  test_rawset_on_the_addon_view_taints_the_slot()
  test_timer_after_callback_keeps_the_scheduling_owner()
  test_a_loadstring_chunk_runs_with_its_builder_taint_assumed()
  test_log_is_capped_and_listeners_hear_each_entry()
  test_nested_frame_does_not_take_the_outer_frames_table_changes()
  test_secret_args_still_follow_context_after_taint()
  test_callsite_skips_taint_module_frames()
end

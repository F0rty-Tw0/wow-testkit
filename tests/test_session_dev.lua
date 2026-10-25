-- Developer report: per-addon load time, heap growth, widgets and unscripted calls credited to the addon that made
-- them, and the nil globals its load errors name, on the DevDemo session.
local A = require("assert")
local Addon = require("addon")
local H = require("tests.helpers.session")
local WorldApi = require("world_api")
local fs = require("fs")

local DEV_DEMO = H.DEMO:gsub("SessionDemo$", "DevDemo")

local function withDev(fn)
  H.withSession({ addonDir = DEV_DEMO }, fn)
end

local function devDemo(sess)
  return sess:call("dev").addons[1]
end

local function test_dev_lists_loaded_addons_in_load_order()
  withDev(function(sess)
    local seq = sess.seq
    local rep = sess:call("dev")
    A.eq(rep.ok, true)
    A.eq(#rep.addons, 1)
    A.eq(rep.addons[1].name, "DevDemo")
    A.contains(rep.notes[2], "estimate")
    A.eq(sess.seq, seq)
  end)
end

local function test_load_time_reads_the_addon_clock()
  local clock = Addon.clock
  local times = { 1.0, 1.25 }
  Addon.clock = function()
    return table.remove(times, 1)
  end
  local ok, err = pcall(withDev, function(sess)
    A.eq(devDemo(sess).loadMs, 250)
  end)
  Addon.clock = clock
  if not ok then
    error(err, 0)
  end
end

-- A temp copy of DevDemo whose TOC leaves out Heavy.lua.
local function lightDevDemo()
  local function read(file)
    return assert(fs.readFile(DEV_DEMO .. "/" .. file))
  end
  local toc = read("DevDemo.toc"):gsub("Heavy%.lua\r?\n", "")
  local files = { ["DevDemo.toc"] = toc, ["Missing.lua"] = read("Missing.lua"), ["MissingNs.lua"] = read("MissingNs.lua") }
  return H.tempAddon("DevDemo", read("Main.lua"), files)
end

-- The kit's own allocations during a load count too, so only the difference Heavy.lua makes is checked. The light load
-- runs first: any warm-up it pays shrinks the difference rather than inflating it. Garbage left by earlier tests stays
-- uncollected on purpose: Addon.load pauses the GC, so a cycle ending mid-load cannot hide the growth.
local function test_memory_estimate_counts_heap_growth_during_load()
  local light
  H.withSession({ addonDir = lightDevDemo() }, function(sess)
    light = devDemo(sess).memoryKb
  end)
  -- Growth, not the whole heap: a world alone holds about 20 MB.
  A.truthy(light < 4000, string.format("memoryKb %.1f without Heavy.lua", light))
  withDev(function(sess)
    local heavy = devDemo(sess).memoryKb
    A.truthy(heavy - light > 500, string.format("memoryKb %.1f with Heavy.lua, %.1f without", heavy, light))
  end)
end

local function test_widgets_are_credited_to_the_creating_addon()
  withDev(function(sess)
    A.same(devDemo(sess).widgets, {
      { type = "Button", count = 1 },
      { type = "FontString", count = 1 },
      { type = "Frame", count = 1 },
      { type = "Texture", count = 1 },
    })
    _G.CreateFrame("Frame")
    A.eq(devDemo(sess).widgets[3].count, 1)
    A.eq(sess:call("fire", { event = "PLAYER_REGEN_DISABLED", args = {}, n = 0 }).ok, true)
    A.same(devDemo(sess).widgets[3], { type = "Frame", count = 2 })
  end)
end

local function test_unscripted_calls_are_credited_to_the_addon()
  withDev(function(sess)
    local expected = { { name = "template:DevDemoNoSuchTemplate", count = 1 } }
    A.same(devDemo(sess).unscripted, expected)
    WorldApi.markUnscripted(sess.w, "kit:probe")
    A.same(devDemo(sess).unscripted, expected)
    A.eq(sess.w.unscripted["kit:probe"], 1)
  end)
end

local function test_missing_globals_come_from_nil_call_errors()
  withDev(function(sess)
    A.same(devDemo(sess).missing, {
      { name = "C_DevDemoNoSuch", kind = "index", count = 1, file = "MissingNs.lua" },
      { name = "DevDemoNoSuchApi", kind = "call", count = 1, file = "Missing.lua" },
    })
  end)
end

return function()
  test_dev_lists_loaded_addons_in_load_order()
  test_load_time_reads_the_addon_clock()
  test_memory_estimate_counts_heap_growth_during_load()
  test_widgets_are_credited_to_the_creating_addon()
  test_unscripted_calls_are_credited_to_the_addon()
  test_missing_globals_come_from_nil_call_errors()
end

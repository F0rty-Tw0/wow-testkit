-- Preview.run: loads an addon, runs a scenario, writes the render snapshot (even when the addon errors), then runs
-- the resolve and PNG steps through Preview.exec, which these tests replace with a recorder.
local A = require("assert")
local Preview = require("preview")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local FIXTURES = TEST_DIR .. "/fixtures/addons"
local PYTHON = os.getenv("TK_PYTHON") or "python"
local NO_EXTRACT_NOTE = "note: no client extract; art falls back to stand-ins"
local ERROR_LINES_SHOWN = 10

-- A temp addon whose Main.lua is body.
local function tempAddon(body)
  local root = Tmp.dir("preview") .. "/TempAddon"
  fs.mkdirp(root)
  fs.writeFile(root .. "/TempAddon.toc", "## Interface: 120100\nMain.lua\n")
  fs.writeFile(root .. "/Main.lua", body)
  return root
end

local FRAME_ADDON = 'local f = CreateFrame("Frame", "TFrame", UIParent)\nf:SetSize(100, 50)\nf:SetPoint("CENTER")\n'

-- Runs fn(calls) with Preview.exec replaced by a recorder; step(argv, log) -> code decides each call's result
-- (default 0). Restored afterwards, whatever fn does.
local function withExec(step, fn)
  local calls, saved = {}, Preview.exec
  Preview.exec = function(argv, log)
    calls[#calls + 1] = argv
    return step and step(argv, log) or 0
  end
  local ok, err = pcall(fn, calls)
  Preview.exec = saved
  if not ok then
    error(err, 0)
  end
end

-- Preview.run(opts); returns the exit code and the collected output.
local function run(opts)
  local out = {}
  local code = Preview.run(opts, function(text)
    out[#out + 1] = text
  end)
  return code, table.concat(out)
end

local function scenarioFile(body)
  local path = Tmp.dir("previewscn") .. "/scn.lua"
  fs.writeFile(path, "return { run = function(s)\n" .. body .. "\nend }\n")
  return path
end

local function test_clean_addon_writes_snapshot_and_runs_resolve()
  withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out })
    local snapshot = assert(fs.readFile(out .. "/snapshot.json"))
    A.eq(code, 0)
    A.contains(snapshot, '"name": "TFrame"')
    A.contains(snapshot, '"ver": 1')
    A.eq(calls[1][1], PYTHON)
    A.eq(calls[1][2]:sub(-#"/tools/preview.py"), "/tools/preview.py")
    A.same({ calls[1][3], calls[1][4], calls[1][5] }, { "resolve", out .. "/snapshot.json", out })
    A.contains(text, "preview: wrote " .. out .. "/snapshot.json")
  end)
end

-- Review Focus 3.
local function test_load_error_still_writes_snapshot_and_exits_1()
  withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    local code, text = run({ addonDir = FIXTURES .. "/PreviewBroken", out = out })
    local snapshot = assert(fs.readFile(out .. "/snapshot.json"))
    A.eq(code, 1)
    A.contains(snapshot, '"PBFrame"')
    A.contains(snapshot, "boom")
    A.contains(text, "error: ")
    A.contains(text, "boom")
    A.eq(calls[1][3], "resolve")
  end)
end

local function test_scenario_error_still_writes_snapshot_and_exits_1()
  withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    local path = scenarioFile('s:login(); error("scenario boom", 0)')
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out, scenario = path })
    A.eq(code, 1)
    A.contains(assert(fs.readFile(out .. "/snapshot.json")), '"TFrame"')
    A.contains(text, "error: scenario boom")
    A.eq(calls[1][3], "resolve")
  end)
end

local function test_error_lines_stop_at_ten()
  withExec(nil, function()
    local path = scenarioFile('s:login()\nfor i = 1, 12 do s.w:recordError("fail" .. i) end')
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = Tmp.dir("previewout"), scenario = path })
    local _, lines = text:gsub("error: ", "")
    A.eq(code, 1)
    A.eq(lines, ERROR_LINES_SHOWN + 1)
    A.contains(text, "error: 2 more not shown")
  end)
end

local function test_size_flag_sets_the_screen()
  withExec(nil, function()
    local out = Tmp.dir("previewout")
    run({ addonDir = tempAddon(FRAME_ADDON), out = out, size = { width = 1280, height = 720 } })
    A.contains(assert(fs.readFile(out .. "/snapshot.json")), '"width": 1280')
  end)
end

local function test_png_flag_runs_the_png_step()
  withExec(nil, function(calls)
    local out, png = Tmp.dir("previewout"), "shot.png"
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out, png = png })
    A.same({ calls[2][3], calls[2][4], calls[2][5], calls[2][6], calls[2][7] }, { "png", out, png, "--size", "1920x1080" })
    A.contains(text, "preview: wrote " .. png)
    A.eq(code, 0)
  end)
end

local function test_failed_step_exits_1_with_its_log()
  local function step(argv, log)
    if argv[3] == "png" then
      fs.writeFile(log, "chrome missing\n")
      return 3
    end
    return 0
  end
  withExec(step, function()
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = Tmp.dir("previewout"), png = "shot.png" })
    A.eq(code, 1)
    A.contains(text, "preview: png failed (exit 3)")
    A.contains(text, "chrome missing")
    A.eq(text:find("preview: wrote shot.png", 1, true), nil)
  end)
end

-- Review Focus 5.
local function test_resolve_log_is_echoed()
  local function step(_, log)
    fs.writeFile(log, NO_EXTRACT_NOTE .. "\n")
    return 0
  end
  withExec(step, function()
    local _, text = run({ addonDir = tempAddon(FRAME_ADDON), out = Tmp.dir("previewout") })
    A.contains(text, NO_EXTRACT_NOTE)
  end)
end

local function test_stale_log_is_not_echoed_by_a_later_step()
  local function step(argv, log)
    if argv[3] == "resolve" then
      fs.writeFile(log, "only resolve says this\n")
    end
    return 0
  end
  withExec(step, function()
    local _, text = run({ addonDir = tempAddon(FRAME_ADDON), out = Tmp.dir("previewout"), png = "shot.png" })
    local _, count = text:gsub("only resolve says this", "")
    A.eq(count, 1)
  end)
end

local function test_scenario_previews_are_numbered_and_resolved()
  withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    local path = scenarioFile('s:login(); s:preview("start"); s:advance(1); s:preview("later")')
    local code = run({ addonDir = tempAddon(FRAME_ADDON), out = out, scenario = path })
    A.eq(code, 0)
    A.truthy(fs.exists(out .. "/1-start/snapshot.json"), "first preview")
    A.truthy(fs.exists(out .. "/2-later/snapshot.json"), "second preview")
    A.eq(#calls, 3)
    A.eq(calls[2][4], out .. "/1-start/snapshot.json")
    A.eq(calls[3][4], out .. "/2-later/snapshot.json")
  end)
end

local function test_addon_skipped_on_the_flavor_exits_2()
  withExec(nil, function(calls)
    local code, text = run({ addonDir = FIXTURES .. "/RetailOnly", out = Tmp.dir("previewout"), flavor = "vanilla" })
    A.eq(code, 2)
    A.contains(text, "skipped")
    A.eq(#calls, 0)
  end)
end

local function test_unreadable_scenario_exits_2()
  withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    local missing = Tmp.dir("previewscn") .. "/nope.lua"
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out, scenario = missing })
    A.eq(code, 2)
    A.contains(text, "cannot read scenario " .. missing)
    local wrongShape = Tmp.dir("previewscn") .. "/shape.lua"
    fs.writeFile(wrongShape, "return 42\n")
    A.eq((run({ addonDir = tempAddon(FRAME_ADDON), out = out, scenario = wrongShape })), 2)
    A.eq(#calls, 0)
  end)
end

local function test_addon_dir_without_a_toc_exits_2()
  withExec(nil, function()
    local code, text = run({ addonDir = Tmp.dir("previewnotoc"), out = Tmp.dir("previewout") })
    A.eq(code, 2)
    A.contains(text, "preview:")
  end)
end

local function test_exec_that_raises_exits_1_after_the_snapshot_is_written()
  local function step()
    error("proc: argument contains a double quote", 0)
  end
  withExec(step, function()
    local out = Tmp.dir("previewout")
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out })
    A.eq(code, 1)
    A.contains(text, "preview: resolve failed: proc: argument contains a double quote")
    A.truthy(fs.exists(out .. "/snapshot.json"), "snapshot written before the step")
  end)
end

return function()
  test_clean_addon_writes_snapshot_and_runs_resolve()
  test_load_error_still_writes_snapshot_and_exits_1()
  test_scenario_error_still_writes_snapshot_and_exits_1()
  test_error_lines_stop_at_ten()
  test_size_flag_sets_the_screen()
  test_png_flag_runs_the_png_step()
  test_failed_step_exits_1_with_its_log()
  test_resolve_log_is_echoed()
  test_stale_log_is_not_echoed_by_a_later_step()
  test_scenario_previews_are_numbered_and_resolved()
  test_addon_skipped_on_the_flavor_exits_2()
  test_unreadable_scenario_exits_2()
  test_addon_dir_without_a_toc_exits_2()
  test_exec_that_raises_exits_1_after_the_snapshot_is_written()
end

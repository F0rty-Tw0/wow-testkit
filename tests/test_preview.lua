-- Preview.run: loads an addon, runs a scenario, writes the render snapshot (even when the addon errors), then runs
-- the resolve and PNG steps through Preview.exec, which these tests replace with a recorder.
local A = require("assert")
local Home = require("home")
local Preview = require("preview")
local ScenarioPreview = require("scenario_preview")
local Toc = require("toc")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local FIXTURES = TEST_DIR .. "/fixtures/addons"
local PYTHON = os.getenv("TK_PYTHON") or "python"
local NO_EXTRACT_NOTE = "note: no client extract; art falls back to stand-ins"
local ERROR_LINES_SHOWN = 10

-- A temp addon whose Main.lua is body; its TOC (so its name) is tocName, default TempAddon.
local function tempAddon(body, tocName)
  local root = Tmp.dir("preview") .. "/TempAddon"
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. (tocName or "TempAddon") .. ".toc", "## Interface: 120100\nMain.lua\n")
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

-- Runs fn(home) with Home.dir pointing at a fresh temp dir, so a default output folder never lands in the real kit home.
local function withHome(fn)
  local home, saved = Tmp.dir("previewhome"), Home.dir
  Home.dir = function()
    return home
  end
  local ok, err = pcall(fn, home)
  Home.dir = saved
  if not ok then
    error(err, 0)
  end
end

-- The default output folder is named after the addon; a name the shell would reinterpret is mapped to underscores.
local function test_default_out_folder_replaces_unsafe_characters_in_the_addon_name()
  withExec(nil, function(calls)
    withHome(function(home)
      local code = run({ addonDir = tempAddon(FRAME_ADDON, "!Odd") })
      A.eq(code, 0)
      A.eq(calls[1][5], home .. "/preview/_Odd")
      A.truthy(fs.exists(home .. "/preview/_Odd/snapshot.json"), "snapshot in the mapped folder")
    end)
  end)
end

local function test_default_out_folder_never_runs_a_command_named_by_the_addon()
  withExec(nil, function(calls)
    withHome(function(home)
      local code = run({ addonDir = tempAddon(FRAME_ADDON, "$(touch X)") })
      A.eq(code, 0)
      A.eq(calls[1][5], home .. "/preview/__touch_X_")
      A.eq(fs.exists("X"), false)
    end)
  end)
end

-- The default folder for each addon name in names (name -> folder), run with Toc.addonName answering that name: a TOC
-- file named NUL.toc cannot be created on windows, since the name opens the NUL device. The addon itself fails to
-- load under a made-up name, but its snapshot, and so the resolve step in calls[1], still comes out.
local function defaultFolders(names)
  local folders, addonName = {}, Toc.addonName
  local ok, err = pcall(function()
    for _, name in ipairs(names) do
      Toc.addonName = function()
        return name
      end
      withExec(nil, function(calls)
        withHome(function(home)
          run({ addonDir = tempAddon(FRAME_ADDON) })
          folders[name] = calls[1] and calls[1][5]:sub(#home + #"/preview/" + 1)
        end)
      end)
    end
  end)
  Toc.addonName = addonName
  assert(ok, err)
  return folders
end

-- Windows opens NUL, con.txt or COM1 as a device and drops a trailing dot, so the folder gets a leading or trailing "_".
local function test_default_out_folder_avoids_windows_device_names_and_trailing_dots()
  local names = { "NUL", "con.txt", "COM1", "Foo.", "Foo..", "Aux", "lpt9.x", "COM10", "Console", "Foo.bar" }
  A.same(defaultFolders(names), {
    NUL = "_NUL",
    ["con.txt"] = "_con.txt",
    COM1 = "_COM1",
    ["Foo."] = "Foo_",
    ["Foo.."] = "Foo__",
    Aux = "_Aux",
    ["lpt9.x"] = "_lpt9.x",
    COM10 = "COM10",
    Console = "Console",
    ["Foo.bar"] = "Foo.bar",
  })
end

-- %w and %d match bytes of a windows locale's letters and digits, which would let COM followed by a superscript one
-- (a device name to windows) through as it is; the folder uses ASCII letters and digits only, one "_" per byte.
local function test_default_out_folder_maps_every_non_ascii_byte_to_an_underscore()
  local names = { "Caf\195\169", "COM\194\185", "LPT\194\178.txt" }
  A.same(defaultFolders(names), {
    ["Caf\195\169"] = "Caf__",
    ["COM\194\185"] = "COM__",
    ["LPT\194\178.txt"] = "LPT__.txt",
  })
end

-- Toc.addonName answers "..", as for a TOC named ...toc: the posix shell fallback of fs.list hides such a dot file.
local function test_addon_named_only_dots_asks_for_out()
  local addonName = Toc.addonName
  Toc.addonName = function()
    return ".."
  end
  local ok, err = pcall(withExec, nil, function(calls)
    withHome(function(home)
      local code, text = run({ addonDir = tempAddon(FRAME_ADDON) })
      A.eq(code, 2)
      A.contains(text, "pass --out")
      A.eq(fs.exists(home .. "/preview"), false)
      A.eq(#calls, 0)
    end)
  end)
  Toc.addonName = addonName
  assert(ok, err)
end

local function test_explicit_out_the_shell_would_expand_exits_2()
  withExec(nil, function(calls)
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = Tmp.dir("previewout") .. '/a"b' })
    A.eq(code, 2)
    A.eq(text:sub(1, #"preview: "), "preview: ")
    A.eq(#calls, 0)
  end)
end

-- The previous run's snapshot and picture must not survive a run that fails, or they read as this run's output.
local function seedStale(out, png)
  fs.writeFile(out .. "/snapshot.json", '{"stale":true}')
  fs.writeFile(png, "stale")
end

local function test_run_whose_snapshot_cannot_be_written_removes_the_previous_snapshot_and_png()
  local write = ScenarioPreview.write
  ScenarioPreview.write = function()
    error("disk full", 0)
  end
  withExec(nil, function(calls)
    local out, png = Tmp.dir("previewout"), Tmp.dir("previewpng") .. "/shot.png"
    seedStale(out, png)
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out, png = png })
    ScenarioPreview.write = write
    A.eq(code, 1)
    A.contains(text, "disk full")
    A.same({ fs.exists(out .. "/snapshot.json"), fs.exists(png), #calls }, { false, false, 0 })
  end)
  ScenarioPreview.write = write
end

-- A --png that is not a .png file (here a notes file) is a usage error before anything runs: deleting it, or the old
-- .png, would lose the user's file.
local function test_png_flag_naming_a_file_that_is_not_a_png_exits_2_and_keeps_it()
  withExec(nil, function(calls)
    local out, notes = Tmp.dir("previewout"), Tmp.dir("previewpng") .. "/notes.md"
    seedStale(out, notes)
    local code, text = run({ addonDir = tempAddon(FRAME_ADDON), out = out, png = notes })
    A.eq(code, 2)
    A.contains(text, "--png must name a .png file")
    A.same({ fs.readFile(notes), fs.readFile(out .. "/snapshot.json"), #calls }, { "stale", '{"stale":true}', 0 })
  end)
end

local function test_png_flag_in_capitals_is_a_png_and_a_failing_run_removes_it()
  local write = ScenarioPreview.write
  ScenarioPreview.write = function()
    error("disk full", 0)
  end
  withExec(nil, function()
    local out, upper = Tmp.dir("previewout"), Tmp.dir("previewpng") .. "/SHOT.PNG"
    seedStale(out, upper)
    local code = run({ addonDir = tempAddon(FRAME_ADDON), out = out, png = upper })
    ScenarioPreview.write = write
    A.same({ code, fs.exists(upper) }, { 1, false })
  end)
  ScenarioPreview.write = write
end

local function test_failed_png_step_leaves_no_previous_png()
  local function step(argv)
    return argv[3] == "png" and 3 or 0
  end
  withExec(step, function()
    local out, png = Tmp.dir("previewout"), Tmp.dir("previewpng") .. "/shot.png"
    seedStale(out, png)
    local code = run({ addonDir = tempAddon(FRAME_ADDON), out = out, png = png })
    A.eq(code, 1)
    A.eq(fs.exists(png), false)
    A.contains(assert(fs.readFile(out .. "/snapshot.json")), '"ver": 1')
  end)
end

return function()
  test_run_whose_snapshot_cannot_be_written_removes_the_previous_snapshot_and_png()
  test_png_flag_naming_a_file_that_is_not_a_png_exits_2_and_keeps_it()
  test_png_flag_in_capitals_is_a_png_and_a_failing_run_removes_it()
  test_failed_png_step_leaves_no_previous_png()
  test_default_out_folder_replaces_unsafe_characters_in_the_addon_name()
  test_default_out_folder_never_runs_a_command_named_by_the_addon()
  test_default_out_folder_avoids_windows_device_names_and_trailing_dots()
  test_default_out_folder_maps_every_non_ascii_byte_to_an_underscore()
  test_addon_named_only_dots_asks_for_out()
  test_explicit_out_the_shell_would_expand_exits_2()
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

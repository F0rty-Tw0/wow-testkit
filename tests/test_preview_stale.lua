-- Preview.run clears the previous run's snapshots from the output folder, so a run that fails (or previews less)
-- leaves nothing to be read as its own output.
local A = require("assert")
local P = require("tests.helpers.preview")
local ScenarioPreview = require("scenario_preview")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local STALE = '{"stale":true}'

local function seed(out, dir)
  fs.mkdirp(out .. "/" .. dir)
  fs.writeFile(out .. "/" .. dir .. "/snapshot.json", STALE)
end

local function test_failing_run_removes_numbered_snapshots_of_an_earlier_run()
  local write = ScenarioPreview.write
  ScenarioPreview.write = function()
    error("disk full", 0)
  end
  P.withExec(nil, function(calls)
    local out = Tmp.dir("previewout")
    seed(out, "1-old")
    seed(out, "12-later_2-x")
    seed(out, "notes")
    local code = P.run({ addonDir = P.tempAddon(P.FRAME_ADDON), out = out })
    ScenarioPreview.write = write
    A.eq(code, 1)
    A.same({ fs.exists(out .. "/1-old/snapshot.json"), fs.exists(out .. "/12-later_2-x/snapshot.json") }, { false, false })
    A.eq(fs.readFile(out .. "/notes/snapshot.json"), STALE)
    A.eq(#calls, 0)
  end)
  ScenarioPreview.write = write
end

local function test_run_with_fewer_previews_leaves_none_of_the_earlier_ones()
  P.withExec(nil, function()
    local out = Tmp.dir("previewout")
    seed(out, "1-old")
    seed(out, "2-older")
    local path = P.scenarioFile('s:login(); s:preview("new")')
    A.eq((P.run({ addonDir = P.tempAddon(P.FRAME_ADDON), out = out, scenario = path })), 0)
    A.contains(assert(fs.readFile(out .. "/1-new/snapshot.json")), '"ver": 1')
    A.same({ fs.exists(out .. "/1-old/snapshot.json"), fs.exists(out .. "/2-older/snapshot.json") }, { false, false })
  end)
end

return function()
  test_failing_run_removes_numbered_snapshots_of_an_earlier_run()
  test_run_with_fewer_previews_leaves_none_of_the_earlier_ones()
end

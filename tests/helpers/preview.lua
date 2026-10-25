-- Shared Preview.run test helpers: a temp addon, a recorder for Preview.exec, a collector for the output text and a
-- scenario file written from a body.
local Preview = require("preview")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local M = {}

M.FRAME_ADDON = 'local f = CreateFrame("Frame", "TFrame", UIParent)\nf:SetSize(100, 50)\nf:SetPoint("CENTER")\n'

-- A temp addon whose Main.lua is body; its TOC (so its name) is tocName, default TempAddon.
function M.tempAddon(body, tocName)
  local root = Tmp.dir("preview") .. "/TempAddon"
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. (tocName or "TempAddon") .. ".toc", "## Interface: 120100\nMain.lua\n")
  fs.writeFile(root .. "/Main.lua", body)
  return root
end

-- Runs fn(calls) with Preview.exec replaced by a recorder; step(argv, log) -> code decides each call's result
-- (default 0). Preview.findClient answers client (default none), so a developer's own extract never reaches a test.
-- Both are restored afterwards, whatever fn does.
function M.withExec(step, fn, client)
  local calls, saved, savedFind = {}, Preview.exec, Preview.findClient
  Preview.exec = function(argv, log)
    calls[#calls + 1] = argv
    return step and step(argv, log) or 0
  end
  Preview.findClient = function()
    return client
  end
  local ok, err = pcall(fn, calls)
  Preview.exec = saved
  Preview.findClient = savedFind
  if not ok then
    error(err, 0)
  end
end

-- Preview.run(opts); returns the exit code and the collected output.
function M.run(opts)
  local out = {}
  local code = Preview.run(opts, function(text)
    out[#out + 1] = text
  end)
  return code, table.concat(out)
end

function M.scenarioFile(body)
  local path = Tmp.dir("previewscn") .. "/scn.lua"
  fs.writeFile(path, "return { run = function(s)\n" .. body .. "\nend }\n")
  return path
end

return M

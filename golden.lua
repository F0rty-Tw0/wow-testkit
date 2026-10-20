-- Golden files: snapshot text kept at <root>/tests/scenarios/golden/<scenario>/<snapshot>.<flavor>.txt with "\n"
-- line endings and a trailing newline. Update writes it; without update, a missing file or a difference is an error.
local M = {}

local A = require("assert")
local fs = require("fs")

local GOLDEN_DIR = "/tests/scenarios/golden/"
local UPDATE_HINT = "rerun with --update to accept the new text"
local MISSING_HINT = "rerun with --update to write it"

local function normalize(text)
  text = text:gsub("\r\n", "\n")
  if text:sub(-1) ~= "\n" then
    text = text .. "\n"
  end
  return text
end

-- Returns "written" (update) or "ok"; errors naming the golden path when it is missing, or with the first
-- differing line and both versions.
function M.check(root, scenario, snapshot, flavor, text, update)
  local dir = root .. GOLDEN_DIR .. scenario
  local path = dir .. "/" .. snapshot .. "." .. flavor .. ".txt"
  text = normalize(text)
  if update == true then
    fs.mkdirp(dir)
    fs.writeFile(path, text)
    return "written"
  end
  local golden = fs.readFile(path)
  if golden == nil then
    error(string.format("golden %s is missing\n  %s", path, MISSING_HINT), 0)
  end
  -- pcall calls A.textEq directly, so its message carries no file:line prefix.
  local same, diff = pcall(A.textEq, text, normalize(golden))
  if same then
    return "ok"
  end
  error(string.format("golden %s: %s\n  %s", path, diff, UPDATE_HINT), 0)
end

return M

-- Scenario previews: s:preview(name) writes the render snapshot of the world as it is now to <out>/<n>-<name>/
-- snapshot.json, where tk preview gave the scenario <out>. M.write is the same writer tk preview uses for the final
-- snapshot.
local M = {}

local Json = require("json")
local Render = require("render")
local fs = require("fs")

-- ASCII classes: %w also takes the bytes of a locale's letters (preview.lua's folderName avoids it for the same reason).
local NAME_PATTERN = "^[A-Za-z0-9_%-]+$"
local JSON_INDENT = 1

-- Writes the render snapshot of s's world, plus the addons map the asset resolver reads, to <dir>/snapshot.json.
function M.write(s, dir)
  local snapshot = Render.snapshot(s.w)
  if s.addon then
    snapshot.addons = { [s.addon] = s.root }
  end
  fs.mkdirp(dir)
  fs.writeFile(dir .. "/snapshot.json", Json.encode(snapshot, JSON_INDENT))
end

function M.extend(Scenario)
  function Scenario:preview(name)
    if type(name) ~= "string" or not name:match(NAME_PATTERN) then
      error("s:preview: name must be letters, digits, '_' or '-'", 2)
    end
    if not self.previewOpts then
      error("s:preview needs an output directory; run through tk preview", 2)
    end
    self.previews = self.previews or {}
    local dir = self.previewOpts.out .. "/" .. (#self.previews + 1) .. "-" .. name
    M.write(self, dir)
    self.previews[#self.previews + 1] = dir
  end
end

return M

-- Game-state fakes: world state a scenario sets with w:setMock / s:mock and the client APIs that read it. Every
-- answer reads w.mock at call time, so a patch applies at once. Each area module installs its own APIs; later tasks
-- add one line to AREAS.
local M = {}

local Group = require("game.group")
local Keys = require("game.keys")
local Session = require("game.session")
local State = require("game.state")

M.define = State.define
M.ALL = State.ALL

local AREAS = { Session, Keys, Group }

-- w.mock is shared with session_state.lua (modifiers, combat, group), so it is created only when absent and each
-- area's defaults fill the keys not yet set.
local function setMock(self, patch)
  if type(patch) ~= "table" then
    error("setMock: patch must be a table", 2)
  end
  State.merge(self.mock, patch)
end

function M.install(w)
  w.mock = w.mock or {}
  w.setMock = setMock
  for _, area in ipairs(AREAS) do
    State.fill(w.mock, area.DEFAULTS)
    area.install(w)
  end
end

return M

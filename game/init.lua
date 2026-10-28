-- Game-state fakes: world state a scenario sets with w:setMock / s:mock and the client APIs that read it. Every
-- answer reads w.mock at call time, so a patch applies at once. Each area module installs its own APIs; later tasks
-- add one line to AREAS.
local M = {}

local ActionBar = require("game.actionbar")
local Addons = require("game.addons")
local Bindings = require("bindings")
local Chat = require("game.chat")
local ClientApi = require("game.clientapi")
local EditMode = require("game.editmode")
local Group = require("game.group")
local Items = require("game.items")
local Keys = require("game.keys")
local Macros = require("game.macros")
local Requests = require("game.requests")
local Session = require("game.session")
local Social = require("game.social")
local Spells = require("game.spells")
local State = require("game.state")
local UnitFrame = require("game.unitframe")
local Zone = require("game.zone")

M.define = State.define
M.ALL = State.ALL

local AREAS = { Session, Keys, Group, Spells, Items, Zone, Addons, Macros, Chat, Social, ActionBar, UnitFrame, EditMode, ClientApi, Requests }

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
  -- A session installs bindings before the addon runs and keeps its loaded keys; any other world gets empty ones.
  if w.bindings == nil then
    Bindings.install(w)
  end
  for _, area in ipairs(AREAS) do
    State.fill(w.mock, area.DEFAULTS)
    area.install(w)
  end
end

return M

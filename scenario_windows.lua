-- Scenario hooks for the Blizzard windows (blizzard_windows.lua): s:openWindow and s:closeWindow fire what the flavor's
-- window code listens for (B2). Tasks 12.3-12.7 register an opener and a closer per window in ScenarioWindows.openers /
-- .closers; a window without one uses the default (load the addon, then the open path).
local M = {}

local BlizzardWindows = require("blizzard_windows")

local ENGINE = "blizzard"
local SHOW, HIDE = "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"

-- openers[window](s, data) and closers[window](s)
M.openers, M.closers = {}, {}

-- Calls the global name (a function) with the global frame under engine context; nothing when either is missing.
local function callOn(s, name, frame)
  local fn, target = _G[name], frame and _G[frame]
  if type(fn) == "function" and target then
    s.w:run(ENGINE, fn, target)
  end
end

-- source: assumed (B2) the order: the window path first (the interaction event, else the window's show global, else its
-- toggle), then the legacy event addons listen for. The show global and the toggle need the layer.
function M.show(s, window)
  local w, spec = s.w, BlizzardWindows.spec(s.w, window)
  if w.blizzard then
    local ok = w:run(ENGINE, BlizzardWindows.loadFor, w, window)
    if not ok then
      s:note("openWindow: " .. spec.addon .. " missing")
    end
  end
  if spec.interaction then
    s:fireIfKnown(SHOW, BlizzardWindows.interaction(spec.interaction))
  end
  if spec.show and w.blizzard and type(_G[spec.show]) == "function" then
    w:run(ENGINE, _G[spec.show])
  end
  if spec.open then
    s:fireIfKnown(spec.open)
  end
  if spec.toggle and w.blizzard and not (spec.interaction or spec.show or spec.open) then
    if type(_G[spec.toggle]) == "function" then
      w:run(ENGINE, _G[spec.toggle])
    elseif spec.frame and _G[spec.frame] then
      w:run(ENGINE, _G[spec.frame].Show, _G[spec.frame])
    end
  end
end

-- source: confirmed (B2) retail handles PLAYER_INTERACTION_MANAGER_FRAME_HIDE in playerinteractionframemanager.lua:174;
-- assumed the show and toggle windows hide through HideUIPanel(<frame>), with the layer on.
function M.hide(s, window)
  local w, spec = s.w, BlizzardWindows.spec(s.w, window)
  if spec.interaction then
    s:fireIfKnown(HIDE, BlizzardWindows.interaction(spec.interaction))
  end
  local frame = spec.frame and _G[spec.frame]
  if w.blizzard and frame and (spec.show or (spec.toggle and frame:IsShown())) then
    callOn(s, "HideUIPanel", spec.frame)
  end
end

local function checked(s, window, verb)
  if not BlizzardWindows.spec(s.w, window) then
    error(verb .. ": unknown window '" .. tostring(window) .. "'", 3)
  end
end

function M.extend(Scenario)
  -- Opens window (the flavor's name for it: talents, map, merchant, mail, auction, transmog) with the data its opener
  -- takes; raises for a window the flavor has no spec for.
  function Scenario:openWindow(window, data)
    checked(self, window, "openWindow")
    local opener = M.openers[window]
    if opener then
      opener(self, data)
    else
      M.show(self, window)
    end
  end

  function Scenario:closeWindow(window)
    checked(self, window, "closeWindow")
    local closer = M.closers[window]
    if closer then
      closer(self)
    else
      M.hide(self, window)
    end
  end
end

return M

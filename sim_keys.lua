-- SimKeys: the sim world's fallback key commands and default keys. The commands are <Bindings> XML in Blizzard's own
-- shapes, so a world without Blizzard's Bindings.xml still walks and presses; Blizzard's file, loaded later, replaces
-- the same-named commands. The default keys bind only keys nothing else bound.
local M = {}

local Bindings = require("bindings")

local ADDON = "SimKit"
local ACTION_BUTTONS = 12

-- source: assumed (spec 7.6; the plan reads Blizzard's game menu Esc handler as `SpellStopCasting() or SpellStopTargeting()`,
-- not re-read here) Esc stops a cast, else the targeting mode, and opens the menu only when neither was there.
local TOGGLE_MENU = "if SpellStopCasting and SpellStopCasting() then return end; "
  .. "if SpellStopTargeting and SpellStopTargeting() then return end; "
  .. "if ToggleGameMenu then ToggleGameMenu() end"

-- source: confirmed (row SM10) movement, action buttons and TARGETNEARESTENEMY are runOnUp and branch on keystate;
-- TOGGLEAUTORUN, OPENALLBAGS and TOGGLEGAMEMENU are not runOnUp (a runOnUp toggle would open on down and close on up).
-- Every body is guarded: a missing global does nothing.
-- NAME -> { body, runOnUp }.
M.COMMANDS = {
  TOGGLEAUTORUN = { body = "if ToggleAutoRun then ToggleAutoRun() end" },
  OPENALLBAGS = { body = "if ToggleAllBags then ToggleAllBags() end" },
  TOGGLEGAMEMENU = { body = TOGGLE_MENU },
  TARGETNEARESTENEMY = {
    body = 'if keystate == "down" and TargetNearestEnemy then TargetNearestEnemy() end',
    runOnUp = true,
  },
}

-- source: confirmed (row SM10) command -> the Start and Stop calls of its walk.
local MOVEMENT = {
  MOVEFORWARD = "MoveForward",
  MOVEBACKWARD = "MoveBackward",
  TURNLEFT = "TurnLeft",
  TURNRIGHT = "TurnRight",
  STRAFELEFT = "StrafeLeft",
  STRAFERIGHT = "StrafeRight",
}

for command, call in pairs(MOVEMENT) do
  local pick = 'local f = keystate == "down" and %sStart or %sStop; if f then f() end'
  M.COMMANDS[command] = { body = pick:format(call, call), runOnUp = true }
end

for n = 1, ACTION_BUTTONS do
  local pick = 'local f = keystate == "down" and ActionButtonDown or ActionButtonUp; if f then f(%d) end'
  M.COMMANDS["ACTIONBUTTON" .. n] = { body = pick:format(n), runOnUp = true }
end

-- source: assumed (row SM9) the retail default keys of these commands: WASD, Q and E to strafe, NUMLOCK for autorun, TAB
-- for the next enemy, B for the bags, ESCAPE for the game menu and 1 to 0, - and = for the twelve action buttons.
-- KEY -> command.
M.KEYS = {
  W = "MOVEFORWARD",
  S = "MOVEBACKWARD",
  A = "TURNLEFT",
  D = "TURNRIGHT",
  Q = "STRAFELEFT",
  E = "STRAFERIGHT",
  NUMLOCK = "TOGGLEAUTORUN",
  TAB = "TARGETNEARESTENEMY",
  B = "OPENALLBAGS",
  ESCAPE = "TOGGLEGAMEMENU",
}

for n, key in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }) do
  M.KEYS[key] = "ACTIONBUTTON" .. n
end

local function markup(name, command)
  local runOnUp = command.runOnUp and ' runOnUp="true"' or ""

  return string.format('<Binding name="%s"%s>%s</Binding>', name, runOnUp, command.body)
end

-- The <Bindings> text of the fallback commands the world does not have yet, or nil when it has them all.
local function missing(w)
  local names = {}
  for name in pairs(M.COMMANDS) do
    if not w.bindings.commands[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    parts[#parts + 1] = markup(name, M.COMMANDS[name])
  end

  return #parts > 0 and "<Bindings>" .. table.concat(parts) .. "</Bindings>" or nil
end

-- Loads the fallback commands the world lacks (an addon's or Blizzard's command of the same name stays) and binds each
-- default key nothing has bound.
function M.install(w)
  -- source: assumed (Ruling R6) the client runs a Blizzard binding secure, so it may call a protected function; the
  -- fallback commands stand in for Blizzard's and run secure too.
  if w.taint then
    w.taint.secureAddons[ADDON] = true
  end
  local xml = missing(w)
  if xml then
    Bindings.loadXml(w, xml, ADDON)
  end
  for key, command in pairs(M.KEYS) do
    if Bindings.lookup(w, key) == nil then
      w.bindings.keys[key] = command
    end
  end
end

return M

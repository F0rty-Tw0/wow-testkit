-- Input state: modifier keys, modified clicks and mouse buttons, read from w.mock. These replace the readers Task 5.4's
-- session state used to install over the same w.mock.modifiers.
local M = {}

local define = require("game.state").define

M.DEFAULTS = {
  modifiers = {},
  -- Overrides of MODIFIED_CLICK_DEFAULTS, action -> "SHIFT" | "CTRL" | "ALT" | "NONE".
  modifiedClicks = {},
  buttons = {},
}

-- source: confirmed (row G7) the SELFCAST, FOCUSCAST, MOUSEOVERCAST, PICKUPACTION and AUTOLOOTTOGGLE defaults of the
-- Settings panel; assumed (row G7) CHATLINK, DRESSUP and SPLITSTACK, which no Lua sets.
local MODIFIED_CLICK_DEFAULTS = {
  CHATLINK = "SHIFT",
  SELFCAST = "ALT",
  FOCUSCAST = "ALT",
  MOUSEOVERCAST = "NONE",
  PICKUPACTION = "SHIFT",
  AUTOLOOTTOGGLE = "SHIFT",
  DRESSUP = "CTRL",
  SPLITSTACK = "SHIFT",
}

-- Function name -> w.mock.modifiers key for the generic and the one-sided readers. A bare key ("shift") counts as the
-- left key.
local SIDES = {
  Shift = "shift",
  Control = "ctrl",
  Alt = "alt",
}
local HELD_NAMES = { SHIFT = "shift", CTRL = "ctrl", ALT = "alt" }

local function left(held, key)
  return held[key] == true or held["l" .. key] == true
end

local function right(held, key)
  return held["r" .. key] == true
end

local function anyHeld(held)
  for _, key in pairs(SIDES) do
    if left(held, key) or right(held, key) then
      return true
    end
  end
  return false
end

-- source: assumed (row G6) the generic readers are true for either side, the Left and Right ones for one side.
local function installModifiers(w)
  for name, key in pairs(SIDES) do
    define(w, "Is" .. name .. "KeyDown", function()
      local held = w.mock.modifiers
      return left(held, key) or right(held, key)
    end)
    define(w, "IsLeft" .. name .. "KeyDown", function()
      return left(w.mock.modifiers, key)
    end)
    define(w, "IsRight" .. name .. "KeyDown", function()
      return right(w.mock.modifiers, key)
    end)
  end
  define(w, "IsModifierKeyDown", function()
    return anyHeld(w.mock.modifiers)
  end)
end

local function modifiedClick(w, action)
  local mock = w.mock
  -- source: assumed (row G7) a bare IsModifiedClick() is true while any modifier is held.
  if action == nil then
    return anyHeld(mock.modifiers)
  end
  local wanted = mock.modifiedClicks[action] or MODIFIED_CLICK_DEFAULTS[action]
  if wanted == nil then
    require("world_api").markUnscripted(w, "IsModifiedClick")
    return false
  end
  local key = HELD_NAMES[wanted]
  return key ~= nil and (left(mock.modifiers, key) or right(mock.modifiers, key))
end

local function mouseButtonDown(w, button)
  local buttons = w.mock.buttons
  if button ~= nil then
    return buttons[button] == true
  end
  for _, down in pairs(buttons) do
    if down then
      return true
    end
  end
  return false
end

function M.install(w)
  installModifiers(w)
  -- source: assumed (row G7) the configured modifier decides; NONE is never held.
  define(w, "IsModifiedClick", function(action)
    return modifiedClick(w, action)
  end)
  -- source: confirmed (row G7) no argument means any mouse button.
  define(w, "IsMouseButtonDown", function(button)
    return mouseButtonDown(w, button)
  end)
  -- source: assumed (row G7) Input.click sets it for the click's duration and restores it after.
  define(w, "GetMouseButtonClicked", function()
    return w.mock.clicked
  end)
end

return M

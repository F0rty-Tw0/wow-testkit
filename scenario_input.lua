-- Scenario input steps: click, enter, leave, type and press on a frame or a global frame name. A step the client
-- would ignore throws "<step>: <reason>" at the scenario's call site.
local M = {}

local Input = require("input")

local ENGINE = "blizzard"
local DEFAULT_BUTTON = "LeftButton"

local function resolve(value)
  if type(value) == "string" then
    return _G[value]
  end
  return value
end

-- Resolves target and returns it, or throws "<step>: <reason>" (level 3: the scenario line that called the step).
local function checked(s, step, target, kind, button)
  local frame = resolve(target)
  local reason = Input.blockedReason(s.w, frame, kind, button)
  if reason then
    error(step .. ": " .. reason, 3)
  end
  return frame
end

function M.extend(Scenario)
  function Scenario:click(target, button)
    button = button or DEFAULT_BUTTON
    local frame = checked(self, "click", target, "click", button)
    self.w:run(ENGINE, Input.click, self.w, frame, button)
  end

  function Scenario:enter(target)
    local frame = checked(self, "enter", target, "enter")
    self.w:run(ENGINE, Input.enter, self.w, frame)
  end

  function Scenario:leave(target)
    local frame = resolve(target)
    if not Input.isFrame(self.w, frame) then
      error("leave: not a frame", 2)
    end
    self.w:run(ENGINE, Input.leave, self.w, frame)
  end

  function Scenario:type(target, text)
    local box = checked(self, "type", target, "type")
    self.w:run(ENGINE, Input.type, self.w, box, text)
  end

  function Scenario:press(target, key)
    local box = checked(self, "press", target, "type")
    self.w:run(ENGINE, Input.press, self.w, box, key)
  end
end

return M

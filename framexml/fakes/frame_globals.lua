-- Frame globals: GetFramesRegisteredForEvent, EnumerateFrames and GetCursorPosition. GetMouseFocus is not installed: no
-- flavor's api lists it (only GetMouseFoci, installed by input.lua).
local M = {}

local API_GATE = { gate = "api" }

local unpack = unpack

-- source: row W55 (confirmed) the frames registered for the event, in dispatch order.
local function registeredFrames(w)
  return function(event)
    return unpack(w.eventFrames[event] or {})
  end
end

-- The first frame created after sequence number seq, nil when none is left. Regions and fonts are skipped.
local function frameAfter(w, seq)
  for candidate = seq + 1, w.ui.seq do
    local widget = w.ui.bySeq[candidate]
    if widget and w.ui.state[widget].plan.isFrame then
      return widget
    end
  end

  return nil
end

-- source: row W55 (confirmed) the frame after `frame` in creation order, the first with no argument, nil at the end.
local function enumerateFrames(w)
  return function(frame)
    local state = frame ~= nil and w.ui.state[frame]
    return frameAfter(w, state and state.seq or 0)
  end
end

-- source: row W55 (confirmed) pixels from the bottom-left corner; 0, 0 with no cursor (assumed). Input.setCursor keeps
-- the cursor from the top-left.
local function cursorPosition(w)
  return function()
    local cursor = w.input.cursor
    if not cursor then
      return 0, 0
    end

    return cursor[1], w.screen.height - cursor[2]
  end
end

function M.install(w)
  w:install("GetFramesRegisteredForEvent", registeredFrames(w), API_GATE)
  w:install("EnumerateFrames", enumerateFrames(w), API_GATE)
  w:install("GetCursorPosition", cursorPosition(w), API_GATE)
end

return M

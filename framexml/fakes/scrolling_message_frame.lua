-- ScrollingMessageFrame: an intrinsic over Frame (like the client's XML, Blizzard_SharedXML/ScrollingMessageFrame.xml:3,
-- `<Frame name="ScrollingMessageFrame" ... intrinsic="true">`, so GetObjectType answers "Frame"). Minimal on purpose:
-- AddMessage, GetNumMessages, Clear, SetMaxLines/GetMaxLines and SetFading/GetFading over st.messages = { { text, r, g, b } },
-- oldest first, for the render snapshot; st.maxLines and st.fading hold what the setters stored.
local M = {}

local Widgets = require("ui.widgets")

local WHITE = 1

-- source: ScrollingMessageFrame.lua:337 `self.historyBuffer = CreateCircularBuffer(120);` and CircularBuffer.lua:46-55
-- (PushFront overwrites the oldest entry once the buffer is full).
local MAX_MESSAGES = 120

-- source: ScrollingMessageFrame.lua:338 `self.shouldFadeAfterInactivity = true;`. Fading is stored and never rendered (W46,
-- assumed: a kit choice).
local DEFAULT_FADING = true

local methods = {}

local function capacity(st)
  return st.maxLines or MAX_MESSAGES
end

-- Drops the oldest lines until at most n are left (CircularBuffer.lua:29-39 drops the oldest element).
local function keepNewest(st, n)
  local messages = st.messages or {}
  while #messages > n do
    table.remove(messages, 1)
  end
end

-- source: ScrollingMessageFrame.lua:10 AddMessage(message, r, g, b, ...) and :737-744 PackageEntry keep r, g, b as passed
-- (nil when omitted; RefreshDisplay then uses the frame's text colour, :634 and :22). White for an omitted colour is
-- assumed: the kit does not model a frame's text colour. The extract (build 70575) confirms it only for a chat frame,
-- whose font object ChatFontNormal is white (blizzard_chatframebase/mainline/chatframeoverrides.lua:4,
-- blizzard_fonts_shared/shared/fonts.xml:1373-1374); a bare frame's colour comes from the engine (still unconfirmed).
function methods.AddMessage(_, _, st, text, r, g, b)
  local messages = st.messages or {}
  st.messages = messages
  messages[#messages + 1] = { text = text ~= nil and tostring(text) or "", r = r or WHITE, g = g or WHITE, b = b or WHITE }
  keepNewest(st, capacity(st))
end

function methods.GetNumMessages(_, _, st)
  return #(st.messages or {})
end

function methods.Clear(_, _, st)
  st.messages = {}
end

-- source: ScrollingMessageFrame.lua:240 SetMaxLines resizes the buffer; shrinking keeps the newest lines.
function methods.SetMaxLines(_, _, st, maxLines)
  st.maxLines = maxLines
  keepNewest(st, capacity(st))
end

function methods.GetMaxLines(_, _, st)
  return capacity(st)
end

-- source: ScrollingMessageFrame.lua:255 SetFading.
function methods.SetFading(_, _, st, fading)
  st.fading = fading and true or false
end

function methods.GetFading(_, _, st)
  if st.fading == nil then
    return DEFAULT_FADING
  end

  return st.fading
end

function M.install(w)
  Widgets.registerIntrinsic(w, "ScrollingMessageFrame", "Frame", methods)
end

return M

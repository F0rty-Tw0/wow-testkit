-- The session console: one ring of the newest lines the addon printed, sent to chat or raised, read by the viewer's
-- console panel. Console.install puts the shims in place (print, the chat frames when absent) and turns each recorded
-- addon error into an error line; Console.push is the one way a line gets in, so the chat fakes call it.
local M = {}

M.SIZE = 500

-- Localized: addon code may assign globals named select or tostring.
local select, tostring = select, tostring

-- Line kinds: print, chat (DEFAULT_CHAT_FRAME), error-frame (UIErrorsFrame), send (SendChatMessage, pushed by game/chat.lua),
-- error (a recorded addon error) and system (the session's own notes, such as an unknown slash command).
function M.push(w, kind, text, r, g, b)
  local ring = w.console
  ring.seq = ring.seq + 1
  local lines = ring.lines
  lines[#lines + 1] = { seq = ring.seq, kind = kind, text = tostring(text), r = r, g = g, b = b }
  if #lines > M.SIZE then
    table.remove(lines, 1)
  end
end

-- The lines with a seq above since, oldest first.
function M.since(w, since)
  local out = {}
  for _, line in ipairs(w.console.lines) do
    if line.seq > since then
      out[#out + 1] = line
    end
  end
  return out
end

local function joined(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring((select(i, ...)))
  end
  return table.concat(parts, " ")
end

local function messageFrame(w, kind)
  return {
    AddMessage = function(_, text, r, g, b)
      M.push(w, kind, text, r, g, b)
    end,
  }
end

-- Each recorded error, message then traceback, also becomes an error line.
local function echoErrors(w)
  local record = w.recordError
  w.recordError = function(self, message, traceback)
    record(self, message, traceback)
    local text = traceback and (tostring(message) .. "\n" .. tostring(traceback)) or message
    M.push(self, "error", text)
  end
end

-- Copies the ring of an earlier session into w's, so a reload keeps the lines and their seq numbers.
function M.carry(w, from)
  w.console.seq = from.seq
  for i, line in ipairs(from.lines) do
    w.console.lines[i] = line
  end
end

-- Sets sess.console = w.console = { seq, lines } and installs the shims through the world, so destroy restores _G.
function M.install(w, sess)
  w.console = { seq = 0, lines = {} }
  sess.console = w.console
  w:set("print", function(...)
    M.push(w, "print", joined(...))
  end)
  for name, kind in pairs({ DEFAULT_CHAT_FRAME = "chat", UIErrorsFrame = "error-frame" }) do
    if rawget(_G, name) == nil then
      w:set(name, messageFrame(w, kind))
    end
  end
  echoErrors(w)
end

return M

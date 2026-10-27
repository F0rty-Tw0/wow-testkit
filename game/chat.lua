-- Chat and sound over w.mock: sent = { { msg, chatType, language, target } }, chatWindows = { [id] = { name, ... } } and
-- played = { { api, ... } } in call order. A sent message also reaches the session console when one is running.
local M = {}

local Console = require("session_console")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

-- source: assumed (row G17) the two default windows and their look; no page lists the starting layout.
M.DEFAULTS = {
  sent = {},
  played = {},
  chatWindows = {
    [1] = { name = "General", fontSize = 14, shown = true, locked = false },
    [2] = { name = "Combat Log", fontSize = 14, shown = true, locked = false },
  },
}

local function installSend(w)
  -- source: confirmed (row G17) the chat type defaults to "SAY".
  local function send(message, chatType, language, target)
    chatType = chatType or "SAY"
    w.mock.sent[#w.mock.sent + 1] = { msg = message, chatType = chatType, language = language, target = target }
    if w.console then
      Console.push(w, "send", "[" .. tostring(chatType) .. "] " .. tostring(message))
    end
  end
  define(w, "C_ChatInfo.SendChatMessage", send)
  -- source: confirmed (row G1) the bare name is Blizzard's deprecation fallback, present on every flavor.
  define(w, "SendChatMessage", send, State.ALL)
  define(w, "GetChatWindowInfo", function(id)
    local window = w.mock.chatWindows[id]
    if not window then
      WorldApi.markUnscripted(w, "GetChatWindowInfo")
      return
    end
    return window.name, window.fontSize, window.r, window.g, window.b, window.alpha, window.shown, window.locked, window.docked, window.uninteractable
  end)
end

local function installSound(w)
  local handles = 0
  local function record(entry)
    w.mock.played[#w.mock.played + 1] = entry
  end
  -- source: confirmed (row G17) the two returns; assumed (row G17) willPlay is always true, the client says nil when a
  -- muted channel prevents it.
  local function play(api, id, channel)
    handles = handles + 1
    record({ api = api, id = id, channel = channel, handle = handles })
    return true, handles
  end
  define(w, "PlaySound", function(soundKitID, channel)
    return play("PlaySound", soundKitID, channel)
  end)
  define(w, "PlaySoundFile", function(sound, channel)
    return play("PlaySoundFile", sound, channel)
  end)
  define(w, "StopSound", function(handle, fadeOut)
    record({ api = "StopSound", handle = handle, fadeOut = fadeOut })
  end)
  define(w, "FlashClientIcon", function()
    record({ api = "FlashClientIcon" })
  end)
end

function M.install(w)
  installSend(w)
  installSound(w)
end

return M

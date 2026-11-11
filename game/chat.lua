-- Chat and sound over w.mock: sent = { { msg, chatType, language, target } }, chatWindows = { [id] = { name, ... } } and
-- played = { { api, ... } } in call order. A sent message also reaches the session console when one is running.
local M = {}

local Console = require("session_console")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

-- source: confirmed (row G36) a real chat-cache.txt: size 12, COLOR 0 0 0 0 (black, alpha 0: the background shows only
-- on hover), LOCKED 1, window 1 SHOWN 1 DOCKED 1, window 2 SHOWN 0 DOCKED 2 (a tab in the General dock), windows 3
-- ("Voice") to 10 (no NAME line) SHOWN 0 DOCKED 0; assumed: DOCKED 0 reads back as nil (Blizzard tests `if docked`).
local function window(name, shown, docked)
  return { name = name, fontSize = 12, r = 0, g = 0, b = 0, alpha = 0, shown = shown, locked = true, docked = docked, uninteractable = false }
end
local chatWindows = { window("General", true, 1), window("Combat Log", false, 2), window("Voice", false) }
for id = 4, 10 do
  chatWindows[id] = window("", false)
end
M.DEFAULTS = {
  sent = {},
  played = {},
  chatWindows = chatWindows,
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

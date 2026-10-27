-- SendChatMessage recording, the chat window list and the sound calls, all over w.mock.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local function test_send_chat_message_is_recorded() -- (G1, G17)
  G.withGame("vanilla", function(w)
    _G.SendChatMessage("hi", "WHISPER", nil, "Bob")
    _G.SendChatMessage("yo")
    A.same(w.mock.sent, { { msg = "hi", chatType = "WHISPER", target = "Bob" }, { msg = "yo", chatType = "SAY" } })
  end)
  G.withGame("retail", function(w)
    _G.C_ChatInfo.SendChatMessage("hi", "GUILD")
    A.same(w.mock.sent, { { msg = "hi", chatType = "GUILD" } })
  end)
end

local function test_bare_send_chat_message_exists_on_every_flavor() -- (G1)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      _G.SendChatMessage("hi", "SAY", "Common")
      A.same(w.mock.sent, { { msg = "hi", chatType = "SAY", language = "Common" } }, flavor)
    end)
  end
end

local function test_send_reaches_the_session_console()
  G.withGame("vanilla", function(w)
    w.console = { seq = 0, lines = {} }
    _G.SendChatMessage("hi", "SAY")
    _G.C_ChatInfo.SendChatMessage("yo")
    A.same({ w.console.lines[1].kind, w.console.lines[1].text }, { "send", "[SAY] hi" })
    A.same({ w.console.lines[2].kind, w.console.lines[2].text }, { "send", "[SAY] yo" })
  end)
end

local function test_chat_window_info_defaults_assumed() -- (G17)
  G.withGame("retail", function(w)
    A.eq((_G.GetChatWindowInfo(1)), "General")
    A.eq((_G.GetChatWindowInfo(2)), "Combat Log")
    A.eq(_G.GetChatWindowInfo(9), nil)
    A.eq(w.unscripted.GetChatWindowInfo, 1)
  end)
end

local function test_sound_calls_are_recorded() -- (G17)
  G.withGame("retail", function(w)
    A.same({ _G.PlaySound(567, "Master") }, { true, 1 })
    A.same({ _G.PlaySoundFile("a.ogg") }, { true, 2 })
    _G.StopSound(1)
    _G.FlashClientIcon()
    local apis = {}
    for i, call in ipairs(w.mock.played) do
      apis[i] = call.api
    end
    A.same(apis, { "PlaySound", "PlaySoundFile", "StopSound", "FlashClientIcon" })
    A.same({ w.mock.played[1].id, w.mock.played[1].channel, w.mock.played[2].id, w.mock.played[3].handle }, { 567, "Master", "a.ogg", 1 })
  end)
end

return function()
  test_send_chat_message_is_recorded()
  test_bare_send_chat_message_exists_on_every_flavor()
  test_send_reaches_the_session_console()
  test_chat_window_info_defaults_assumed()
  test_sound_calls_are_recorded()
end

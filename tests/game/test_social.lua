-- The Battle.net, instance, guild, chat channel, club, house editor, restriction and template reads that
-- WhisperMessenger makes without a scenario faking them, all over w.mock; plus the bindings and drag calls of Task 5.6
-- answering in every world.
local A = require("assert")
local Bindings = require("bindings")
local Game = require("game")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")
local Scenario = require("scenario")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TOC = "## Interface: 120100\n## Interface-Mists: 50504\n## Interface-Vanilla: 11509\n## Interface-TBC: 20506\n"
  .. "## Interface-Forever: 16001\nWMShape.lua\n"
-- Every call below is one WhisperMessenger makes at login or in its first use.
local SHAPE = [[
local function call(name, ...)
  local fn
  if name:find("%.") then
    fn = _G[name:match("^(.-)%.")][name:match("%.(.+)$")]
  else
    fn = _G[name]
  end
  if fn then
    fn(...)
  end
end
call("issecretvalue", 1); call("BNGetInfo"); call("BNGetNumFriends"); call("GetBindingKey", "TOGGLEWHISPER")
call("GetInstanceInfo"); call("IsInGuild"); call("C_PartyInfo.IsGUIDInGroup", "Player-1-1"); call("GetChannelList")
call("GetChannelName", 1); call("C_ChatInfo.InChatMessagingLockdown"); call("C_ChatInfo.RegisterAddonMessagePrefix", "WM")
call("C_Club.GetGuildClubId"); call("C_Club.GetSubscribedClubs"); call("C_HouseEditor.IsHouseEditorActive")
call("C_RestrictedActions.IsAddOnRestrictionActive", 0); call("C_XMLUtil.GetTemplateInfo", "Nope")
call("Ambiguate", "Bob-Silvermoon", "none")
CreateFrame("Button"):RegisterForDrag("LeftButton")
]]

local function test_wm_shape_addon_leaves_nothing_unscripted() -- (G18)
  local root = Tmp.dir("social")
  fs.mkdirp(root .. "/WMShape")
  fs.writeFile(root .. "/WMShape/WMShape.toc", TOC)
  fs.writeFile(root .. "/WMShape/WMShape.lua", SHAPE)
  local results = Scenario.matrix({ "retail", "vanilla" }, function(s)
    s:login()
  end, { addon = "WMShape", root = root .. "/WMShape" })
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    A.same(results[flavor].unscripted, {}, flavor)
    A.eq(results[flavor].status, "pass", flavor)
  end
end

-- source: confirmed wiki API_Ambiguate context table; assumed a character on another realm is not in the guild (the kit
-- has no guild roster).
local function test_ambiguate_follows_the_context_table_assumed()
  G.withGame("retail", function(w)
    w:setMock({ realm = "Argent Dawn" })
    local same, other = "Bob-ArgentDawn", "Bob-Silvermoon"
    for context, want in pairs({
      all = { "Bob", other },
      none = { "Bob", other },
      guild = { "Bob", other },
      short = { "Bob", "Bob" },
      mail = { same, other },
    }) do
      A.same({ _G.Ambiguate(same, context), _G.Ambiguate(other, context) }, want, context)
    end
    A.eq(_G.Ambiguate("Bob", "mail"), "Bob")
  end)
end

local function test_battle_net_reads_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.same({ _G.BNGetInfo() }, { 1, "Viewer#1234", 1, "", false, false, false })
    A.same({ _G.BNGetNumFriends() }, { 0, 0 })
    w:setMock({ bnet = { battleTag = "Other#99" }, friends = 3 })
    A.eq(select(2, _G.BNGetInfo()), "Other#99")
    A.eq((_G.BNGetNumFriends()), 3)
  end)
end

local function test_instance_info_follows_the_mock() -- (G9)
  G.withGame("retail", function(w)
    w:setMock({ instance = { type = "party", name = "Deadmines", difficultyID = 1 } })
    local info = { _G.GetInstanceInfo() }
    A.eq(select("#", _G.GetInstanceInfo()), 11)
    A.same({ info[1], info[2], info[3], info[4], info[5], info[6], info[7], info[8], info[9] }, {
      "Deadmines",
      "party",
      1,
      "",
      0,
      0,
      false,
      0,
      0,
    })
    A.same({ _G.IsInInstance() }, { true, "party" })
  end)
end

local function test_open_world_instance_info_assumed() -- (G9)
  G.withGame("retail", function()
    local name, kind, difficultyID, _, _, _, _, instanceID = _G.GetInstanceInfo()
    A.same({ name, kind, difficultyID, instanceID }, { "Eastern Kingdoms", "none", 0, 0 })
  end)
end

local function test_in_guild_follows_the_guild_count_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.eq(_G.IsInGuild(), false)
    w:setMock({ guild = { total = 12 } })
    A.eq(_G.IsInGuild(), true)
  end)
end

local function test_channels_follow_the_mock_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.same({ _G.GetChannelList() }, {})
    A.same({ _G.GetChannelName(1) }, { 0 })
    w:setMock({ channels = { { name = "General" }, { name = "Trade", disabled = true } } })
    A.same({ _G.GetChannelList() }, { 1, "General", false, 2, "Trade", true })
    A.same({ _G.GetChannelName(2) }, { 2, "Trade", 0 })
    A.same({ _G.GetChannelName("general") }, { 1, "General", 0 })
  end)
end

local function test_addon_message_prefix_is_recorded_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.same({ _G.C_ChatInfo.RegisterAddonMessagePrefix("WM") }, { true })
    _G.C_ChatInfo.RegisterAddonMessagePrefix("WM")
    _G.C_ChatInfo.RegisterAddonMessagePrefix("Other")
    A.same(w.mock.prefixes, { "WM", "Other" })
    A.eq(_G.C_ChatInfo.InChatMessagingLockdown(), false)
  end)
end

local function test_clubs_follow_the_mock_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.eq(_G.C_Club.GetGuildClubId(), nil)
    A.same(_G.C_Club.GetSubscribedClubs(), {})
    A.same({ _G.C_Club.GetClubInfo("1") }, {})
    w:setMock({ guildClubId = "77", clubs = { { clubId = "77", name = "Guild" } } })
    A.eq(_G.C_Club.GetGuildClubId(), "77")
    A.same(_G.C_Club.GetSubscribedClubs(), { { clubId = "77", name = "Guild" } })
    A.same(_G.C_Club.GetClubInfo("77"), { clubId = "77", name = "Guild" })
    w:setMock({ guildClubId = false })
    A.eq(_G.C_Club.GetGuildClubId(), nil)
  end)
end

local function test_restrictions_template_info_and_house_editor_assumed() -- (G18)
  G.withGame("retail", function(w)
    A.eq(_G.C_HouseEditor.IsHouseEditorActive(), false)
    A.eq(_G.C_RestrictedActions.IsAddOnRestrictionActive(0), false)
    w:setMock({ restrictions = { [0] = 2, [5] = 1 } })
    A.same({ _G.C_RestrictedActions.IsAddOnRestrictionActive(0), _G.C_RestrictedActions.IsAddOnRestrictionActive(5) }, { true, false })
    A.same({ _G.C_XMLUtil.GetTemplateInfo("Nope") }, {})
    w:setMock({ templateInfo = { Plain = { type = "Frame", width = 10, height = 20 } } })
    A.same(_G.C_XMLUtil.GetTemplateInfo("Plain"), { type = "Frame", width = 10, height = 20 })
    A.eq(w.unscripted["C_XMLUtil.GetTemplateInfo"], nil)
  end)
end

local function test_party_guid_is_not_in_the_group_assumed() -- (G18)
  G.withGame("retail", function()
    A.eq(_G.C_PartyInfo.IsGUIDInGroup("Player-1-1"), false)
    A.eq(_G.IsGUIDInGroup, nil)
  end)
end

local function test_issecretvalue_follows_the_world_assumed() -- (G18)
  G.withGame("vanilla", function(w)
    A.eq(_G.issecretvalue("x"), false)
    w.isSecret = function(value)
      return value == "hidden"
    end
    A.same({ _G.issecretvalue("hidden"), _G.issecretvalue("x") }, { true, false })
  end)
end

local function test_task_5_6_bindings_and_drag_answer_outside_a_session()
  G.withGame("retail", function(w)
    A.same({ _G.GetBindingKey("TOGGLEWHISPER") }, {})
    _G.SetBinding("F5", "TOGGLEWHISPER")
    A.eq((_G.GetBindingKey("TOGGLEWHISPER")), "F5")
    local b = _G.CreateFrame("Button")
    b:RegisterForDrag("LeftButton", "RightButton")
    A.same(w.ui.state[b].dragButtons, { "LeftButton", "RightButton" })
    A.eq(w.unscripted["Button:RegisterForDrag"], nil)
  end)
end

local function test_game_install_keeps_bindings_a_session_installed_first()
  H.withWorld("retail", function(w)
    Bindings.install(w)
    _G.SetBinding("F6", "KEPT")
    Game.install(w)
    A.eq((_G.GetBindingKey("KEPT")), "F6")
  end)
end

return function()
  test_wm_shape_addon_leaves_nothing_unscripted()
  test_ambiguate_follows_the_context_table_assumed()
  test_battle_net_reads_assumed()
  test_instance_info_follows_the_mock()
  test_open_world_instance_info_assumed()
  test_in_guild_follows_the_guild_count_assumed()
  test_channels_follow_the_mock_assumed()
  test_addon_message_prefix_is_recorded_assumed()
  test_clubs_follow_the_mock_assumed()
  test_restrictions_template_info_and_house_editor_assumed()
  test_party_guid_is_not_in_the_group_assumed()
  test_issecretvalue_follows_the_world_assumed()
  test_task_5_6_bindings_and_drag_answer_outside_a_session()
  test_game_install_keeps_bindings_a_session_installed_first()
end

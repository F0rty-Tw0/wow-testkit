-- The viewer's Blizzard panel on the session side (session_blizzard.lua): the snapshot's session.blizzard block, a reload
-- that toggles the layer, and the state patches for action slots and the active Edit Mode layout. Every extract here is
-- a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Json = require("json")
local Layout = require("ui.layout")
local SessionH = require("tests.helpers.session")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local function layerOpts(targets)
  local ex = B.extract(Tmp.dir("sbz"), B.mini())
  return { blizzardUi = { targets = targets }, extract = ex.dir }
end

local function reload(host, body)
  return Json.decode(host:handleJson("reload", Json.encode(body)))
end

local function layout(name, point, x, y)
  local anchor = { point = point, relativeTo = "UIParent", relativePoint = point, offsetX = x, offsetY = y }
  local system = { system = 0, isInDefaultPosition = false, anchorInfo = anchor, settings = {} }
  return { layoutName = name, layoutType = 1, systems = { system } }
end

local function test_reload_toggles_the_layer()
  SessionH.withHost(layerOpts({ "Blizzard_MiniBar" }), function(host)
    A.eq(reload(host, { blizzardUi = false }).ok, true)
    local off = host.sess:call("snapshot")
    A.same({ off.session.blizzard.enabled, SessionH.item(off, "MiniBar") }, { false, nil })
    A.eq(reload(host, { blizzardUi = true }).ok, true)
    local on = host.sess:call("snapshot")
    A.eq(on.session.blizzard.enabled, true)
    A.truthy(SessionH.item(on, "MiniBar") ~= nil, "the layer's targets come back")
    local refused = reload(host, { blizzardUi = "yes" })
    A.eq(refused.ok, false)
    A.contains(refused.error, "blizzardUi")
    A.eq(host.sess.loads, 3, "a refused reload leaves the session alone")
  end)
end

-- Without --extract the layer would fall back to Client.find and load the developer's own extract.
local function test_reload_refuses_the_layer_without_an_extract()
  SessionH.withHost({}, function(host)
    local refused = reload(host, { blizzardUi = true })
    A.eq(refused.ok, false)
    A.contains(refused.error, "extract")
    A.same({ host.sess.loads, host.sess.s.blizzardUi }, { 1, nil })
    A.eq(reload(host, { blizzardUi = false }).ok, true, "turning the layer off needs no extract")
  end)
end

local function test_state_actions_update_the_button()
  SessionH.withSession(layerOpts({ "Blizzard_MiniButtons" }), function(sess)
    A.eq(sess:call("state", { actions = { [1] = { texture = 136235, count = 3 } } }).ok, true)
    A.same({ _G.MiniBarButton1.Icon:GetTexture(), _G.MiniBarButton1.Count:GetText() }, { 136235, "3" })
    A.eq(sess:call("state", { actions = { ["1"] = false } }).ok, true, "a JSON object key names the slot too")
    A.eq(_G.MiniBarButton1.Icon:GetTexture(), nil)
    local bad = sess:call("state", { actions = { ["x"] = {} } })
    A.eq(bad.ok, false)
    A.contains(bad.error, "'x'")
    A.eq(sess:call("state", { actions = { [0] = {} } }).ok, false, "slots start at 1")
    A.eq(sess:call("state", { actions = { [2] = 5 } }).ok, false, "a slot is fields or false")
  end)
end

local function test_state_actions_survive_a_reload_and_encode()
  SessionH.withHost(layerOpts({ "Blizzard_MiniButtons" }), function(host)
    local reply = Json.decode(host:handleJson("state", '{"actions":{"5":{"texture":7}}}'))
    A.same(reply.state.actions, { ["5"] = { texture = 7 } })
    A.eq(reload(host, {}).ok, true)
    A.eq(_G.C_ActionBar.GetActionTexture(5), 7)
  end)
end

local function test_state_edit_mode_active_moves_the_frame()
  SessionH.withSession(layerOpts({ "Blizzard_MiniEditMode" }), function(sess)
    sess.s:editMode({ layouts = { layout("A", "BOTTOM", 0, 45), layout("B", "TOPLEFT", 10, -20) }, active = 3 })
    A.eq(sess:call("state", { editMode = { active = 4 } }).ok, true)
    A.eq(Layout.rect(sess.w, _G.MiniBar).left, 10)
    A.eq(sess:call("snapshot").session.blizzard.active, 4)
    local bad = sess:call("state", { editMode = { active = 9 } })
    A.eq(bad.ok, false)
    A.contains(bad.error, "active")
    A.eq(sess:call("state", { editMode = { active = 1.5 } }).ok, false)
    A.eq(sess:call("state", { editMode = { name = "A" } }).ok, false, "only active can be set")
    A.eq(sess.w.mock.editMode.active, 4)
  end)
end

-- A WTF folder with one account holding a config, a bindings file and an Edit Mode cache of two layouts.
local function wtfDir()
  local dir = Tmp.dir("sbzwtf")
  local files = {
    ["config-cache.wtf"] = 'SET cameraDistanceMaxZoomFactor "2.6"\nSET Sound_MasterVolume "0.2"\n',
    ["bindings-cache.wtf"] = "bind K MINI_TOGGLE\nbind A STRAFELEFT\nbind B STRAFERIGHT\n",
    ["edit-mode-cache-account.txt"] = "1 0 1 A 0 1 B 0\0",
  }
  fs.mkdirp(dir .. "/Account/ACC")
  for name, text in pairs(files) do
    fs.writeFile(dir .. "/Account/ACC/" .. name, text)
  end
  return dir
end

local function test_summary_lists_layouts_and_wtf_counts()
  SessionH.withHost({ wtfDir = wtfDir() }, function(host)
    local info = host.sess:call("snapshot").session.blizzard
    A.same({ info.available, info.layouts, info.active }, { false, { "A", "B" }, 3 })
    A.same(info.wtf, { cvars = 2, bindings = 3, saved = 0, layouts = 2 })
  end)
  SessionH.withSession(layerOpts({ "Blizzard_MiniBar" }), function(sess)
    local info = sess:call("snapshot").session.blizzard
    A.same({ info.available, info.layouts, info.wtf }, { true, {}, nil })
  end)
end

return function()
  test_reload_toggles_the_layer()
  test_reload_refuses_the_layer_without_an_extract()
  test_state_actions_update_the_button()
  test_state_actions_survive_a_reload_and_encode()
  test_state_edit_mode_active_moves_the_frame()
  test_summary_lists_layouts_and_wtf_counts()
end

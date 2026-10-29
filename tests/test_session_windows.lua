-- The viewer's window picker (Task 12.8): POST /state { window = "<name>" | "close" } opens a Blizzard window with its
-- windows_demo.lua entry, closing the open one first, and session.blizzard lists the windows and the open one. The extract
-- is a kit-authored mini one (tests/helpers/blizzard.lua, tests/helpers/windows.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local SessionH = require("tests.helpers.session")
local Tmp = require("tests.helpers.tmp")
local W = require("tests.helpers.windows")

local SPECS = {
  talents = { addon = "Blizzard_MiniTalents", toggle = "MiniToggleTalents", frame = "MiniTalentFrame" },
  map = { addon = "Blizzard_MiniWorldMap", toggle = "MiniToggleWorldMap", frame = "MiniMapFrame" },
  merchant = { addon = "Blizzard_MiniMerchant", open = "MERCHANT_SHOW", frame = "MiniMerchantFrame" },
  mail = { addon = "Blizzard_MiniWindow", open = "MAIL_SHOW", frame = "MiniWindowFrame" },
  auction = { addon = "Blizzard_MiniAuction", open = "AUCTION_HOUSE_SHOW", frame = "MiniAuctionFrame" },
  transmog = { addon = "Blizzard_MiniTransmog", open = "TRANSMOGRIFY_OPEN", frame = "MiniTransmogFrame" },
}

-- The mini merchant also hides on MERCHANT_CLOSED, as the client's merchant window does on that event.
local MINIS = {
  blizzard_miniauction = W.MINI.blizzard_miniauction,
  blizzard_minitransmog = W.MINI.blizzard_minitransmog,
  blizzard_minimerchant = {
    toc = "## Interface: 120100\n## LoadOnDemand: 1\nMiniMerchant.lua\nMiniClose.lua\n",
    files = {
      ["miniclose.lua"] = [[
local f = MiniMerchantFrame
local onEvent = f:GetScript("OnEvent")
f:RegisterEvent("MERCHANT_CLOSED")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "MERCHANT_CLOSED" then
    HideUIPanel(self)
  else
    onEvent(self, event, ...)
  end
end)
]],
    },
  },
}

local function withWindows(fn)
  local ex = B.extract(Tmp.dir("sw"), B.mini(MINIS))
  SessionH.withSession({ extract = ex.dir, blizzardUi = { targets = { "Blizzard_MiniBase" } } }, function(sess)
    sess.w.windowSpecs = SPECS
    fn(sess)
  end)
end

local function test_state_window_opens_and_closes_the_merchant()
  withWindows(function(sess)
    local reply = sess:call("state", { window = "merchant" })
    local snap = sess:call("snapshot")
    A.same({ reply.ok, SessionH.item(snap, "MiniMerchantFrame") ~= nil, snap.session.blizzard.open }, { true, true, "merchant" })
    sess:call("state", { window = "close" })
    snap = sess:call("snapshot")
    A.same({ SessionH.item(snap, "MiniMerchantFrame"), snap.session.blizzard.open }, { nil, nil })
  end)
end

local function test_state_window_switches_by_closing_first()
  withWindows(function(sess)
    local log = W.watch(sess.w, { "MERCHANT_CLOSED", "MAIL_SHOW" })
    sess:call("state", { window = "merchant" })
    sess:call("state", { window = "mail" })
    A.same(W.names(log), { "MERCHANT_CLOSED", "MAIL_SHOW" })
    A.eq(sess:call("snapshot").session.blizzard.open, "mail")
  end)
end

local function test_unknown_window_is_rejected_before_the_world()
  withWindows(function(sess)
    local seq = sess.seq
    local reply = sess:call("state", { window = "bank" })
    A.eq(reply.ok, false)
    A.contains(reply.error, "'bank'")
    A.eq(sess.seq, seq)
  end)
end

local function test_summary_lists_available_windows()
  withWindows(function(sess)
    A.same(sess:call("snapshot").session.blizzard.windows, { "auction", "mail", "map", "merchant", "talents", "transmog" })
  end)
end

local function test_flavor_without_the_window_is_rejected_before_the_world()
  SessionH.withSession({ flavor = "tbc" }, function(sess)
    local seq = sess.seq
    local reply = sess:call("state", { window = "transmog" })
    A.same({ reply.ok, reply.error }, { false, "state: no 'transmog' window on tbc" })
    A.eq(sess.seq, seq)
  end)
end

-- Beyond the plan (lead brief): a window the layer cannot show (layer off, or its addon not in the extract) is refused too,
-- so the picker and the HTTP endpoint accept the same names.
local function test_window_not_available_is_rejected_before_the_world()
  SessionH.withSession({}, function(sess)
    local seq = sess.seq
    local reply = sess:call("state", { window = "merchant" })
    A.same({ reply.ok, reply.error }, { false, "state: no 'merchant' window available (the Blizzard UI layer is off)" })
    A.eq(sess.seq, seq)
  end)
end

return function()
  test_state_window_opens_and_closes_the_merchant()
  test_state_window_switches_by_closing_first()
  test_unknown_window_is_rejected_before_the_world()
  test_summary_lists_available_windows()
  test_flavor_without_the_window_is_rejected_before_the_world()
  test_window_not_available_is_rejected_before_the_world()
end

-- The merchant and mail openers and closers (Task 12.5): which events fire in which order per flavor (B2, B10, B12), the
-- one classic addon both windows share (B1) and item-name hydration from DB2 (B17). Extracts are kit-authored mini ones.
local A = require("assert")
local B = require("tests.helpers.blizzard")
local BlizzardWindows = require("blizzard_windows")
local W = require("tests.helpers.windows")

local STOCK = {
  items = {
    { itemID = 6948, name = "Kit Stone", texture = 134414, price = 100 },
    { itemID = 159, name = "Kit Water", texture = 132794, price = 25 },
  },
}
local MAIL =
  { inbox = { { sender = "Kit Sender", subject = "Hello", items = { { itemID = 159, name = "Kit Water", texture = 132794, count = 5 } } } } }

-- (B10; the order and MERCHANT_CLOSED are assumed)
local function test_open_merchant_on_the_classic_family_fires_show_then_update_assumed()
  W.scenario("tbc", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" })
    s:openWindow("merchant", STOCK)
    A.same(W.names(log), { "MERCHANT_SHOW", "MERCHANT_UPDATE" })
    A.eq(_G.GetMerchantNumItems(), 2)
    s:closeWindow("merchant")
    A.same(W.names(log), { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" })
    A.eq(_G.GetMerchantNumItems(), 2)
  end)
end

local function test_open_merchant_on_retail_and_forever_fires_the_interaction_event_first_assumed()
  for _, flavor in ipairs({ "retail", "forever" }) do
    W.scenario(flavor, {}, function(s)
      local log = W.watch(
        s.w,
        { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }
      )
      s:openWindow("merchant", STOCK)
      A.same(W.names(log), { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MERCHANT_SHOW", "MERCHANT_UPDATE" }, flavor)
      A.eq(log[1][3], 5, flavor)
      s:closeWindow("merchant")
      A.same({ log[4][1], log[4][3], log[5][1] }, { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5, "MERCHANT_CLOSED" }, flavor)
    end)
  end
end

-- (B12; MAIL_SHOW and MAIL_CLOSED are assumed)
local function test_open_mail_fires_show_then_inbox_update()
  W.scenario("tbc", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" })
    s:openWindow("mail", MAIL)
    A.same(W.names(log), { "MAIL_SHOW", "MAIL_INBOX_UPDATE" })
    A.same({ _G.GetInboxNumItems() }, { 1, 1 })
    s:closeWindow("mail")
    A.same(W.names(log), { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" })
  end)
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MAIL_SHOW", "MAIL_INBOX_UPDATE" })
    s:openWindow("mail", MAIL)
    A.same(W.names(log), { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MAIL_SHOW", "MAIL_INBOX_UPDATE" })
    A.eq(log[1][3], 17)
  end)
end

-- (B1, C3, R12-a) one folder, one flavor-suffixed TOC, both windows
local CLASSIC = {
  blizzard_uipanels_game = {
    toc = "## Interface: 20506\nClassic.lua\n",
    tocFile = "blizzard_uipanels_game_classic.toc",
    files = {
      ["classic.lua"] = [[
MiniClassicLoads = (MiniClassicLoads or 0) + 1
for _, name in ipairs({ "MerchantFrame", "MailFrame" }) do
  CreateFrame("Frame", name, UIParent):Hide()
end
function MerchantFrame_MerchantShow() MerchantFrame:Show() end
function MailFrame_Show() MailFrame:Show() end
]],
    },
  },
}
local function test_mail_and_merchant_open_one_classic_addon()
  B.run(B.mini(CLASSIC), { flavor = "tbc", header = "Interface-TBC: 20506" }, function(s)
    A.same({ _G.MiniClassicLoads, (_G.C_AddOns.IsAddOnLoaded("Blizzard_UIPanels_Game")) }, { 1, true })
    s:openWindow("merchant", STOCK)
    s:openWindow("mail", MAIL)
    A.same({ _G.MiniClassicLoads, _G.MerchantFrame:IsShown(), _G.MailFrame:IsShown() }, { 1, true, true })
    A.same(BlizzardWindows.available(s.w), { "mail", "merchant" })
    s:closeWindow("merchant")
    A.eq(_G.MerchantFrame:IsShown(), false)
  end)
end

-- (assumed) Blizzard's show global raising does not stop the opener: the error is the layer's, the legacy event still fires
local BROKEN = {
  blizzard_uipanels_game = {
    toc = "## Interface: 20506\nClassic.lua\n",
    tocFile = "blizzard_uipanels_game_classic.toc",
    files = {
      ["classic.lua"] = [[
CreateFrame("Frame", "MailFrame", UIParent):Hide()
function MailFrame_Show() error("kit boom") end
]],
    },
  },
}
local function test_a_show_global_that_raises_goes_to_the_layer_errors_assumed()
  B.run(B.mini(BROKEN), { flavor = "tbc", header = "Interface-TBC: 20506" }, function(s)
    local before = #s.w.blizzard.errors
    local log = W.watch(s.w, { "MAIL_INBOX_UPDATE" })
    s:openWindow("mail", MAIL)
    A.same({ #s.w.blizzard.errors - before, W.names(log) }, { 1, { "MAIL_INBOX_UPDATE" } })
  end)
end

-- (B17) names come from ItemSparse and Item; (assumed) without an extract a row left unnamed is "Kit item <id>"
local DB2 = {
  itemsparse = "return { [900100] = { Display_lang = 'Kit Hydrated', OverallQualityID = 1 } }",
  item = "return { [900100] = { IconFileDataID = 134414 } }",
}
local function test_open_merchant_hydrates_item_names_from_db2()
  W.scenario("vanilla", { db2 = DB2 }, function(s)
    s:openWindow("merchant", { items = { { itemID = 900100, price = 5 } } })
    A.same({ _G.GetMerchantItemInfo(1) }, { "Kit Hydrated", 134414, 5, 1, -1, true, true, false })
  end)
end

local function test_open_mail_hydrates_attachments_from_db2()
  W.scenario("vanilla", { db2 = DB2 }, function(s)
    s:openWindow("mail", { inbox = { { sender = "A", subject = "B", items = { { itemID = 900100 } } } } })
    A.same({ _G.GetInboxItem(1, 1) }, { "Kit Hydrated", 900100, 134414, 1, 1, true, false })
  end)
end

local function test_open_merchant_without_an_extract_names_unnamed_rows_assumed()
  W.scenario("vanilla", {}, function(s)
    s:openWindow("merchant", { items = { { itemID = 900100, price = 5 }, { itemID = 6948, name = "Kit Stone" } } })
    A.same({ (_G.GetMerchantItemInfo(1)), (_G.GetMerchantItemInfo(2)) }, { "Kit item 900100", "Kit Stone" })
  end)
end

local function test_reopening_replaces_the_stock()
  W.scenario("tbc", {}, function(s)
    s:openWindow("merchant", STOCK)
    s:openWindow("merchant", { items = { { itemID = 1, name = "Kit One" } } })
    A.eq(_G.GetMerchantNumItems(), 1)
  end)
end

return function()
  test_open_merchant_on_the_classic_family_fires_show_then_update_assumed()
  test_open_merchant_on_retail_and_forever_fires_the_interaction_event_first_assumed()
  test_open_mail_fires_show_then_inbox_update()
  test_mail_and_merchant_open_one_classic_addon()
  test_a_show_global_that_raises_goes_to_the_layer_errors_assumed()
  test_open_merchant_hydrates_item_names_from_db2()
  test_open_mail_hydrates_attachments_from_db2()
  test_open_merchant_without_an_extract_names_unnamed_rows_assumed()
  test_reopening_replaces_the_stock()
end

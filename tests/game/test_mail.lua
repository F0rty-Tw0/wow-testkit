-- Inbox counts, headers, text and attachments, read from w.mock.mail (B12, B13).
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local INBOX = {
  inbox = {
    {
      sender = "Kit Sender",
      subject = "Hello",
      money = 500,
      daysLeft = 29.5,
      body = "Body text",
      stationeryMiddle = "KitMid",
      stationeryEdge = "KitEdge",
      isTakeable = true,
      items = { { itemID = 159, name = "Kit Water", texture = 132794, count = 5, quality = 1 } },
    },
  },
  newMail = true,
  senders = { "Kit Sender" },
}

local function test_inbox_counts_and_header() -- (B12)
  G.withGame("tbc", function(w)
    w:setMock({ mail = INBOX })
    A.same({ _G.GetInboxNumItems() }, { 1, 1 })
    local _, _, sender, subject, money, cod, days, itemCount, wasRead, wasReturned = _G.GetInboxHeaderInfo(1)
    A.same({ sender, subject, money, cod, days, itemCount, wasRead, wasReturned }, { "Kit Sender", "Hello", 500, 0, 29.5, 1, false, false })
  end)
end

local function test_header_icons_default_to_the_first_item_assumed() -- (B12)
  G.withGame("tbc", function(w)
    w:setMock({ mail = INBOX })
    A.eq((_G.GetInboxHeaderInfo(1)), 132794)
    w:setMock({ mail = { inbox = { { packageIcon = 1, stationeryIcon = 2 } } } })
    A.same({ _G.GetInboxHeaderInfo(1) }, { 1, 2, "Kit Sender", "Hello", 500, 0, 29.5, 1, false, false, false, true, false, 5, 159 })
  end)
end

-- (B12: the Classic MailFrame reads 15; the extras and defaults assumed)
local function test_header_returns_fifteen_values_with_the_first_item_assumed()
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      w:setMock({ mail = INBOX })
      A.eq(select("#", _G.GetInboxHeaderInfo(1)), 15, flavor)
      local v = { select(8, _G.GetInboxHeaderInfo(1)) }
      A.same({ v[1], v[2], v[3], v[4], v[5], v[6], v[7] }, { 1, false, false, false, true, false, 5 }, flavor) -- itemCount .. firstItemQuantity
      if flavor == "retail" or flavor == "forever" then
        A.contains(v[8], "|Hitem:159:", flavor) -- firstItemLink
      else
        A.eq(v[8], 159, flavor) -- firstItemID
      end
    end)
  end
end

local function test_body_attachment_and_flags() -- (B12)
  G.withGame("retail", function(w)
    w:setMock({ mail = INBOX })
    A.same({ _G.GetInboxText(1) }, { "Body text", "KitMid", "KitEdge", true, false, false }) -- bodyText .. isConsortium (6 values)
    A.same({ _G.GetInboxItem(1, 1) }, { "Kit Water", 159, 132794, 5, 1, true, false }) -- 7 values: the last is isCurrency
    A.same({ _G.HasNewMail(), _G.C_Mail.HasInboxMoney(1), _G.GetLatestThreeSenders() }, { true, true, "Kit Sender" })
    A.eq(_G.C_Mail.CanCheckInbox(), true)
    A.contains(_G.GetInboxItemLink(1, 1), "|Hitem:159:")
  end)
end

local function test_mail_without_items_has_no_item_count()
  G.withGame("tbc", function(w)
    w:setMock({ mail = { inbox = { { sender = "A", subject = "B" } } } })
    local v = { _G.GetInboxHeaderInfo(1) }
    A.same({ v[1], v[8], v[14], v[15] }, {}) -- no package icon, no item count, no first item
    A.same({ _G.GetInboxItem(1, 1) }, {})
  end)
end

local function test_taking_money_records_and_keeps_it() -- (B13)
  G.withGame("tbc", function(w)
    w:setMock({ mail = INBOX })
    _G.TakeInboxMoney(1)
    _G.CheckInbox()
    A.same({ w.mock.requests[1].api, w.mock.requests[2].api, (select(5, _G.GetInboxHeaderInfo(1))) }, { "TakeInboxMoney", "CheckInbox", 500 })
  end)
end

return function()
  test_inbox_counts_and_header()
  test_header_icons_default_to_the_first_item_assumed()
  test_header_returns_fifteen_values_with_the_first_item_assumed()
  test_body_attachment_and_flags()
  test_mail_without_items_has_no_item_count()
  test_taking_money_records_and_keeps_it()
end

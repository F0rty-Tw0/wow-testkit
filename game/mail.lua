-- The inbox, read from w.mock.mail at call time: { inbox = { { sender, subject, money = 0, cod = 0, daysLeft = 30, wasRead =
-- false, wasReturned = false, textCreated = false, canReply = true, isGM = false, body = "", stationeryMiddle?,
-- stationeryEdge?, isTakeable = false, isInvoice = false, isConsortium = false, packageIcon?, stationeryIcon?, items = { {
-- itemID, name?, texture?, count = 1, quality?, canUse = true, isCurrency = false } } } }, newMail = false, senders = {} }.
-- An attachment without a name, texture or quality reads the item store. The mail calls only record a request (B13).
local M = {}

local Items = require("game.items")
local Requests = require("game.requests")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

local unpack = unpack

M.DEFAULTS = { mail = { inbox = {}, newMail = false, senders = {} } }

local ATTACHMENT_LINK_FLAVORS = { retail = true, forever = true }

-- The mail at index; nothing, counted as unscripted under name, for an index with no mail.
local function mailAt(w, index, name)
  local mail = type(index) == "number" and w.mock.mail.inbox[index]
  if not mail then
    WorldApi.markUnscripted(w, name)
  end
  return mail
end

-- The attachment at slot; nothing, and not unscripted: the window asks every slot of a mail.
local function attachmentAt(mail, slot)
  return type(slot) == "number" and (mail.items or {})[slot] or nil
end

-- source: confirmed (B12) 15 values (retail 70575 mailframe.lua:214, Classic MailFrame at 2cfec7c): the wiki's 13, then the first
-- attachment's count and its itemID (vanilla, tbc, mists) or link (retail, forever). Assumed: the defaults the store leaves
-- open, the package icon being the first attachment's texture, and no attachments being nil rather than 0 (the window tests
-- `not itemCount`, mailframe.lua:423).
local function header(w, index)
  local mail = mailAt(w, index, "GetInboxHeaderInfo")
  if not mail then
    return
  end
  local items = mail.items or {}
  local first = items[1]
  local _, texture = Items.rowFacts(w, first or {})
  local firstRef = first and first.itemID
  if first and ATTACHMENT_LINK_FLAVORS[w.flavor] then
    firstRef = Items.rowLink(w, first)
  end
  return mail.packageIcon or texture,
    mail.stationeryIcon,
    mail.sender,
    mail.subject,
    mail.money or 0,
    mail.cod or 0,
    mail.daysLeft or 30,
    #items > 0 and #items or nil,
    mail.wasRead == true,
    mail.wasReturned == true,
    mail.textCreated == true,
    mail.canReply ~= false,
    mail.isGM == true,
    first and (first.count or 1),
    firstRef
end

-- source: confirmed (B12) six values, the window reads the first five; assumed the body defaults to "" and the flags to false.
local function text(w, index)
  local mail = mailAt(w, index, "GetInboxText")
  if mail then
    return mail.body or "", mail.stationeryMiddle, mail.stationeryEdge, mail.isTakeable == true, mail.isInvoice == true, mail.isConsortium == true
  end
end

-- source: confirmed (B12) seven values, the last is isCurrency; assumed count 1, usable, not currency, and the quality of the
-- item store when the attachment has none.
local function attachment(w, index, slot)
  local mail = mailAt(w, index, "GetInboxItem")
  local item = mail and attachmentAt(mail, slot)
  if item then
    local name, texture, record = Items.rowFacts(w, item)
    return name, item.itemID, texture, item.count or 1, item.quality or record.quality, item.canUse ~= false, item.isCurrency == true
  end
end

local function installReads(w)
  define(w, "GetInboxNumItems", function()
    local count = #w.mock.mail.inbox
    return count, count
  end)
  define(w, "GetInboxHeaderInfo", function(index)
    return header(w, index)
  end)
  define(w, "GetInboxText", function(index)
    return text(w, index)
  end)
  define(w, "GetInboxItem", function(index, slot)
    return attachment(w, index, slot)
  end)
  define(w, "GetInboxItemLink", function(index, slot)
    local mail = mailAt(w, index, "GetInboxItemLink")
    local item = mail and attachmentAt(mail, slot)
    return item and Items.rowLink(w, item)
  end)
  define(w, "HasNewMail", function()
    return w.mock.mail.newMail == true
  end)
  define(w, "GetLatestThreeSenders", function()
    return unpack(w.mock.mail.senders, 1, 3)
  end)
  define(w, "C_Mail.HasInboxMoney", function(index)
    local mail = mailAt(w, index, "C_Mail.HasInboxMoney")
    return mail ~= nil and (mail.money or 0) > 0
  end)
  -- source: assumed the client can always check the mailbox the kit shows.
  define(w, "C_Mail.CanCheckInbox", function()
    return true
  end)
end

-- source: assumed (B13) the calls change nothing here; the scenario plays the server's reply.
local REQUESTS = { "CheckInbox", "TakeInboxItem", "TakeInboxMoney", "DeleteInboxItem", "SendMail", "AutoLootMailItem" }

function M.install(w)
  installReads(w)
  for _, name in ipairs(REQUESTS) do
    define(w, name, function(...)
      Requests.record(w, name, ...)
    end)
  end
end

return M

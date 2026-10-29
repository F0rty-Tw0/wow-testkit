-- Demo data for s:openWindow, one entry per Blizzard window (Phase 12): kit-authored values over the extract's DB2 geometry
-- (docs/client-sources.md B17). A scenario passes an entry as the opener's data: s:openWindow("talents", demo.talents).

-- One TransmogOutfitSlotInfo (api/retail/TransmogOutfitInfo.lua): slot is an Enum.TransmogOutfitSlot value, collectionType an
-- Enum.TransmogCollectionType value, slotName the inventory slot name the window's Lua passes to GetInventorySlotInfo.
local function slot(slotID, collectionType, slotName)
  return { slot = slotID, type = 0, collectionType = collectionType, slotName = slotName, isSecondary = false }
end

return {
  -- The classic family reads unspent, ranks and classFile (tabs and talents come from the extract); the trait window reads
  -- treeID and ranks. Each opener ignores the other's keys. kit is the stand-in store for a run with no extract.
  talents = {
    classFile = "WARRIOR",
    unspent = 5,
    treeID = 790,
    kit = {
      unspent = 5,
      tabs = {
        {
          name = "Kit Tree",
          talents = {
            { name = "Kit Strike", tier = 1, column = 1, rank = 2, maxRank = 3 },
            { name = "Kit Rage", tier = 2, column = 1, rank = 0, maxRank = 1, prereqs = { { tier = 1, column = 1 } } },
          },
        },
      },
      traits = {
        trees = { [790] = { nodes = { 1, 2 } } },
        nodes = {
          [1] = {
            posX = 600,
            posY = 600,
            maxRanks = 2,
            ranksPurchased = 1,
            visibleEdges = { { targetNode = 2, type = 1, visualStyle = 0, isActive = false } },
          },
          [2] = { posX = 600, posY = 1200, maxRanks = 1 },
        },
      },
    },
  },
  -- The zone the player stands in, by flavor (ids of the installed extracts' UiMap rows; the map art comes from the extract).
  map = {
    mapIDs = { retail = 37, tbc = 1429 },
    position = { x = 0.4, y = 0.6 },
  },
  -- Item ids only: the names and icons come from the extract's DB2 (a run with no extract calls them "Kit item <id>").
  -- Prices, stock and the repair bill are kit-authored.
  merchant = {
    items = {
      { itemID = 159, price = 25, stackCount = 5 },
      { itemID = 4540, price = 25, stackCount = 5 },
      { itemID = 117, price = 50, stackCount = 5, numAvailable = 3 },
      { itemID = 2070, price = 100 },
    },
    buyback = { { itemID = 2589, price = 13, quantity = 2 } },
    canRepair = true,
    repairCost = 1234,
  },
  mail = {
    newMail = true,
    senders = { "Kit Merchant", "Kit Friend" },
    inbox = {
      {
        sender = "Kit Merchant",
        subject = "Your order",
        money = 500,
        daysLeft = 29.5,
        body = "Thank you for your order.",
        items = { { itemID = 159, count = 5 } },
      },
      { sender = "Kit Friend", subject = "Hello", daysLeft = 12, wasRead = true, body = "See you in the city." },
    },
  },
  -- Item ids only: the names and icons come from the extract's DB2 (a run with no extract calls them "Kit item <id>"). One
  -- entry holds both families' results: the classic window reads list, the retail window browse, items and commodities.
  -- Prices and quantities are kit-authored.
  auction = {
    list = {
      { itemID = 2589, count = 20, quality = 1, minBid = 100, minIncrement = 5, buyout = 400, owner = "Kit Seller", timeLeft = 3 },
      { itemID = 159, count = 5, quality = 1, minBid = 25, minIncrement = 1, buyout = 60, owner = "Kit Seller", timeLeft = 2 },
      { itemID = 25, quality = 1, minBid = 90, minIncrement = 4, buyout = 150, owner = "Kit Friend", timeLeft = 4 },
    },
    browse = {
      { itemKey = { itemID = 2589 }, totalQuantity = 40, minPrice = 20, containsOwnerItem = false },
      { itemKey = { itemID = 159 }, totalQuantity = 12, minPrice = 12, containsOwnerItem = false },
      { itemKey = { itemID = 25 }, totalQuantity = 1, minPrice = 150, containsOwnerItem = false },
    },
    commodities = {
      [2589] = {
        { itemID = 2589, quantity = 30, unitPrice = 20, auctionID = 1, numOwnerItems = 0 },
        { itemID = 2589, quantity = 10, unitPrice = 25, auctionID = 2, numOwnerItems = 0 },
      },
    },
  },
  -- Retail, forever and mists only (tbc and vanilla have no transmog window). Item ids and visual ids are rows of the
  -- installed extract's ItemModifiedAppearance (visualID = ItemAppearanceID; a run with no extract has no
  -- sources); item names and icons come from the extract, the collected flags are kit-authored, as the server's would be.
  -- Category keys are Enum.TransmogCollectionType values (Shirt 5, Feet 11).
  transmog = {
    items = { 6096, 6097, 6120, 6125, 6122, 6127 },
    categories = { [5] = { name = "Kit Shirt" }, [11] = { name = "Kit Feet" } },
    appearances = {
      [5] = {
        { visualID = 1968, isCollected = true, uiOrder = 1 },
        { visualID = 1969, isCollected = true, uiOrder = 2 },
        { visualID = 1974, uiOrder = 3 },
        { visualID = 1979, uiOrder = 4 },
      },
      [11] = { { visualID = 1976, isCollected = true, uiOrder = 1 }, { visualID = 1981, uiOrder = 2 } },
    },
    sourceInfo = { [2248] = { isCollected = true }, [2249] = { isCollected = true }, [2257] = { isCollected = true } },
    -- The slot layout is kit-authored (no installed file lists which slot sits in which group): the left and right columns of
    -- the armor slots and the weapons along the bottom, one appearance slot each.
    slotGroups = {
      {
        position = 0, -- Enum.TransmogOutfitSlotPosition.Left
        appearanceSlotInfo = {
          slot(0, 1, "HEADSLOT"),
          slot(1, 2, "SHOULDERSLOT"),
          slot(3, 3, "BACKSLOT"),
          slot(4, 4, "CHESTSLOT"),
          slot(6, 5, "SHIRTSLOT"),
          slot(5, 6, "TABARDSLOT"),
          slot(7, 7, "WRISTSLOT"),
        },
        illusionSlotInfo = {},
      },
      {
        position = 1, -- Right
        appearanceSlotInfo = { slot(8, 8, "HANDSSLOT"), slot(9, 9, "WAISTSLOT"), slot(10, 10, "LEGSSLOT"), slot(11, 11, "FEETSLOT") },
        illusionSlotInfo = {},
      },
      {
        position = 2, -- Bottom
        appearanceSlotInfo = { slot(12, 0, "MAINHANDSLOT"), slot(13, 0, "SECONDARYHANDSLOT") },
        illusionSlotInfo = {},
      },
    },
    outfits = { { outfitID = 1, name = "Kit Outfit" } },
    activeOutfitID = 1,
  },
}

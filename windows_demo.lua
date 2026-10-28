-- Demo data for s:openWindow, one entry per Blizzard window (Phase 12): kit-authored values over the extract's DB2 geometry
-- (docs/client-sources.md B17). A scenario passes an entry as the opener's data: s:openWindow("talents", demo.talents).
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
}

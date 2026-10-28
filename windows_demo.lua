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
}

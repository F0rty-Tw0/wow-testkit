-- Scenario fixture for `tk test`: hovers a player and snapshots the unit tooltip.
local BOB = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80 }

return {
  run = function(s)
    s:login()
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    s:snapshot("tooltip", _G.GameTooltip)
  end,
}

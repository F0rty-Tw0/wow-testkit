-- Scenario fixture for the Clicky addon: clicks, hovers and types, then notes the addon's event log.
return {
  run = function(s)
    s:login()
    s:click("ClickyButton")
    s:click("ClickyCheck")
    s:enter("ClickyButton")
    s:enter("ClickyCheck")
    s:unit("mouseover", { name = "Bob" })
    s:hover("mouseover")
    s:type("ClickyBox", "hi")
    s:press("ClickyBox", "ENTER")
    -- UIDropDownMenu menu (Task 3.6)
    s:click("ClickyMenuButton")
    s:snapshot("dropdown_menu", s:menu())
    s:enter(s:menu().levels[1].entries[8].frame)
    s:snapshot("dropdown_submenu", s:menu())
    s:pick({ "More", "Nested" })
    s:closeMenus()
    s:note("log: " .. table.concat(s.ns.log, ";"))
  end,
}

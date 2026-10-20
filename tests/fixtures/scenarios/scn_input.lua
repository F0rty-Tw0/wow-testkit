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
    s:note("log: " .. table.concat(s.ns.log, ";"))
  end,
}

-- Scenario fixture for Scenario.runFile: logs in on every flavor.
return {
  run = function(s)
    s:login()
  end,
}

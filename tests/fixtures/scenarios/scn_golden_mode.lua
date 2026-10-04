-- Scenario fixture for Scenario.runFile: fails unless the run turned golden mode on.
return {
  run = function(s)
    assert(s.w.goldenMode == true, "golden mode is off")
  end,
}

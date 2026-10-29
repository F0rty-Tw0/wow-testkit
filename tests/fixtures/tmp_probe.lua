-- Prints the folder Tmp.dir makes, for scripts/test.sh: a single-file run51 run must leave no such folder behind.
local Tmp = require("tests.helpers.tmp")

return function()
  print("TMP " .. Tmp.dir("probe"))
end

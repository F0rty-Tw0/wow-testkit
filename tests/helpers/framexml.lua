-- FrameXML test helpers: a world with widgets and the stage-1 FrameXML fakes installed, always destroyed.
local H = require("tests.helpers.world")
local FrameXML = require("framexml.fakes")

local M = {}

function M.withFrameXML(flavor, fn)
  H.withWorld(flavor, function(w)
    FrameXML.installStage1(w)
    fn(w)
  end)
end

return M

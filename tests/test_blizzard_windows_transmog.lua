-- The transmog window (Task 12.7): the opener writes the transmog store and the window reads it back through the
-- C_TransmogCollection API. The plan lists this test in test_blizzard_windows.lua, which is at its 300-line limit, so it
-- lives here. The extract is a kit-authored mini one (tests/helpers/windows.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local W = require("tests.helpers.windows")

local SPEC = { transmog = { addon = "Blizzard_MiniTransmog", open = "TRANSMOGRIFY_OPEN", frame = "MiniTransmogFrame" } }
local TM = {
  categories = { [1] = { name = "Kit Head" } },
  appearances = { [1] = { { visualID = 501, isCollected = true }, { visualID = 502 } } },
}

local function test_transmog_window_lists_appearances()
  B.run(B.mini({ blizzard_minitransmog = W.MINI.blizzard_minitransmog }), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SPEC
    end,
  }, function(s)
    s:openWindow("transmog", TM)
    A.same({ _G.MiniTransmogFrame:IsShown(), _G.MiniTransmogFrame.Count:GetText() }, { true, "1/2" })
    s:closeWindow("transmog")
    A.eq(_G.C_Transmog.IsAtTransmogNPC(), false)
  end)
end

return function()
  test_transmog_window_lists_appearances()
end

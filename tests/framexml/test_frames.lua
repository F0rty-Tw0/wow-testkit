-- Lazy Blizzard frame names: names in Ketho's Frames list resolve to inert frames, counted as unscripted.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_known_frame_name_resolves_to_frame_counted_unscripted()
  withFrameXML("retail", function(w)
    A.eq(_G.ChatFrame1:GetObjectType(), "Frame")
    A.eq(_G.ChatFrame1, _G.ChatFrame1)
    A.eq(w.unscripted["frame:ChatFrame1"], 1)
  end)
end

local function test_unknown_name_stays_nil()
  withFrameXML("retail", function()
    A.eq(_G.NotAFrameName, nil)
  end)
end

local function test_existing_globals_metatable_index_still_answers()
  local fallback = { Fallback = 1 }
  setmetatable(_G, { __index = fallback })
  local ok, err = pcall(withFrameXML, "retail", function()
    A.eq(_G.Fallback, 1)
    A.eq(_G.ChatFrame1:GetObjectType(), "Frame")
  end)
  setmetatable(_G, nil)
  assert(ok, err)
end

return function()
  test_known_frame_name_resolves_to_frame_counted_unscripted()
  test_unknown_name_stays_nil()
  test_existing_globals_metatable_index_still_answers()
end

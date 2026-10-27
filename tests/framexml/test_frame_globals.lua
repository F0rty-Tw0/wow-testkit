-- Frame globals (framexml/fakes/frame_globals.lua): GetFramesRegisteredForEvent, EnumerateFrames and GetCursorPosition.
-- Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function newFrame()
  return _G.CreateFrame("Frame", nil, _G.UIParent)
end

local function test_registered_frames_come_back_in_dispatch_order() -- W55
  withFrameXML("retail", function()
    local a, b, c = newFrame(), newFrame(), newFrame()
    b:RegisterEvent("PLAYER_LOGIN")
    a:RegisterEvent("PLAYER_LOGIN")
    c:RegisterEvent("PLAYER_ENTERING_WORLD")
    A.same({ _G.GetFramesRegisteredForEvent("PLAYER_LOGIN") }, { b, a })
    A.same({ _G.GetFramesRegisteredForEvent("PLAYER_ENTERING_WORLD") }, { c })
  end)
end

local function test_an_event_nobody_registered_returns_nothing() -- W55
  withFrameXML("retail", function()
    A.eq(select("#", _G.GetFramesRegisteredForEvent("PLAYER_LOGIN")), 0)
  end)
end

local function test_an_unregistered_frame_leaves_the_list() -- W55
  withFrameXML("retail", function()
    local a, b = newFrame(), newFrame()
    a:RegisterEvent("PLAYER_LOGIN")
    b:RegisterEvent("PLAYER_LOGIN")
    a:UnregisterEvent("PLAYER_LOGIN")
    A.same({ _G.GetFramesRegisteredForEvent("PLAYER_LOGIN") }, { b })
  end)
end

local function test_enumerate_frames_walks_creation_order() -- W55
  withFrameXML("retail", function()
    local first = _G.EnumerateFrames()
    A.eq(first, _G.UIParent)
    local a, b = newFrame(), newFrame()
    A.eq(_G.EnumerateFrames(a), b)
    A.eq(_G.EnumerateFrames(b), nil)
  end)
end

local function test_enumerate_frames_skips_regions() -- W55
  withFrameXML("retail", function()
    local a = newFrame()
    a:CreateTexture()
    local b = newFrame()
    A.eq(_G.EnumerateFrames(a), b)
  end)
end

local function test_cursor_position_is_zero_without_a_cursor() -- W55
  withFrameXML("retail", function()
    A.same({ _G.GetCursorPosition() }, { 0, 0 })
  end)
end

local function test_cursor_position_has_its_origin_at_the_bottom_left() -- W55
  withFrameXML("retail", function(w)
    Input.setCursor(w, 30, 40)
    A.same({ _G.GetCursorPosition() }, { 30, 1040 })
    Input.setCursor(w, nil)
    A.same({ _G.GetCursorPosition() }, { 0, 0 })
  end, { screen = { width = 1920, height = 1080 } })
end

local function test_get_mouse_focus_is_defined_on_no_flavor() -- W55
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      A.eq(rawget(_G, "GetMouseFocus"), nil, flavor)
    end)
  end
end

return function()
  test_registered_frames_come_back_in_dispatch_order()
  test_an_event_nobody_registered_returns_nothing()
  test_an_unregistered_frame_leaves_the_list()
  test_enumerate_frames_walks_creation_order()
  test_enumerate_frames_skips_regions()
  test_cursor_position_is_zero_without_a_cursor()
  test_cursor_position_has_its_origin_at_the_bottom_left()
  test_get_mouse_focus_is_defined_on_no_flavor()
end

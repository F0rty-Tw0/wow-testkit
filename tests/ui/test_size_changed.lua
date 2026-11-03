-- OnSizeChanged (row LY16): a frame's size change reaches its OnSizeChanged(width, height) at the next sim step, from
-- its own setters or from its anchors, and at once when a measurement resolves it (ui/layout_size.lua).
local A = require("assert")
local H = require("tests.helpers.sim")
local HW = require("tests.helpers.widgets")

local function frame(parent)
  return _G.CreateFrame("Frame", nil, parent or _G.UIParent)
end

local function recorder(f)
  local calls = {}
  f:SetScript("OnSizeChanged", function(self, width, height)
    calls[#calls + 1] = { self == f, width, height }
  end)

  return calls
end

local function test_a_set_size_fires_at_the_next_step_once()
  H.withSim("retail", {}, function(_, s)
    local f = frame()
    f:SetPoint("CENTER")
    local calls = recorder(f)
    f:SetSize(100, 40)
    A.same(calls, {}) -- a setter only marks the rect stale
    s:simStep(0.1)
    A.same(calls, { { true, 100, 40 } })
    s:simStep(0.1)
    A.same(calls, { { true, 100, 40 } })
  end)
end

local function test_an_anchored_frame_fires_when_its_parent_resizes()
  H.withSim("retail", {}, function(_, s)
    local parent = frame()
    parent:SetPoint("CENTER")
    parent:SetSize(200, 100)
    local child = frame(parent)
    child:SetPoint("TOPLEFT", 10, -10)
    child:SetPoint("BOTTOMRIGHT", -10, 10)
    local calls = recorder(child)
    s:simStep(0.1)
    parent:SetHeight(150)
    s:simStep(0.1)
    A.same(calls, { { true, 180, 80 }, { true, 180, 130 } })
  end)
end

local function test_visible_frames_fire_in_creation_order_and_a_hidden_one_once_shown()
  H.withSim("retail", {}, function(_, s)
    local order = {}
    local first, second, third = frame(), frame(), frame()
    for _, entry in ipairs({ { third, "third" }, { second, "second" }, { first, "first" } }) do
      entry[1]:SetScript("OnSizeChanged", function()
        order[#order + 1] = entry[2]
      end)
      entry[1]:SetSize(1, 1)
    end
    second:Hide()
    s:simStep(0.1)
    A.same(order, { "first", "third" })
    second:Show()
    s:simStep(0.1)
    A.same(order, { "first", "third", "second" })
  end)
end

local function test_a_measurement_fires_at_once()
  HW.withWidgets("retail", function()
    local f = frame()
    local calls = recorder(f)
    f:SetWidth(30)
    A.eq(f:GetWidth(), 30)
    A.same(calls, { { true, 30, 0 } })
    f:GetSize()
    A.same(calls, { { true, 30, 0 } })
  end)
end

-- The told size is stored before the handler runs: a handler that measures its own frame (common in addon code)
-- is not told again from inside that measurement.
local function test_a_handler_that_measures_itself_is_told_once()
  H.withSim("retail", {}, function(_, s)
    local f = frame()
    f:SetPoint("CENTER")
    local calls = 0
    f:SetScript("OnSizeChanged", function(self)
      calls = calls + 1
      self:GetWidth()
    end)
    f:SetSize(10, 20)
    s:simStep(0.1)
    A.eq(calls, 1)
  end)
end

-- Blizzard's ScrollBox clears its OnSizeChanged around its own measurements (scrollbox.lua:156-193): a change seen
-- with no handler is spent, so restoring the handler does not replay it.
local function test_a_change_measured_with_no_handler_is_not_replayed()
  H.withSim("retail", {}, function(_, s)
    local f = frame()
    f:SetPoint("CENTER")
    local calls = recorder(f)
    local handler = f:GetScript("OnSizeChanged")
    f:SetScript("OnSizeChanged", nil)
    f:SetSize(5, 6)
    f:GetHeight()
    f:SetScript("OnSizeChanged", handler)
    s:simStep(0.1)
    A.same(calls, {})
  end)
end

return function()
  test_a_set_size_fires_at_the_next_step_once()
  test_an_anchored_frame_fires_when_its_parent_resizes()
  test_visible_frames_fire_in_creation_order_and_a_hidden_one_once_shown()
  test_a_measurement_fires_at_once()
  test_a_handler_that_measures_itself_is_told_once()
  test_a_change_measured_with_no_handler_is_not_replayed()
end

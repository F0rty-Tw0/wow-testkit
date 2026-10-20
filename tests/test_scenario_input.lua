-- Input steps: click, enter, leave, type and press on frames and names, blocked-step errors.
local A = require("assert")
local Flavors = require("tools.flavors")
local Clicky = require("tests.helpers.clicky")
local Scenario = require("scenario")
local Rec = require("tests.helpers.input")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local HOVER = { addon = "Hover", root = TEST_DIR .. "/fixtures/addons/Hover" }
local EXPECTED_LOG = table.concat({
  "ClickyButton:click:LeftButton:false",
  "ClickyCheck:click:checked=true",
  "ClickyButton:enter:true",
  "ClickyButton:leave:true",
  "ClickyCheck:enter:true",
  "ClickyCheck:leave:true",
  "ClickyBox:text:h:true",
  "ClickyBox:text:hi:true",
  "ClickyBox:enter-pressed:hi",
}, ";")

-- A Scenario on flavor with the Hover addon (never logged in), always destroyed.
local function withScenario(flavor, fn)
  local s = Scenario.new({ addon = HOVER.addon, root = HOVER.root, flavor = flavor })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_click_resolves_a_name_and_a_frame()
  withScenario("retail", function(s)
    local b = _G.CreateFrame("Button", "StepBtn", _G.UIParent)
    b:RegisterForClicks("AnyUp")
    local log = Rec.record(b, { "OnClick" })
    s:click("StepBtn")
    s:click(b, "RightButton")
    A.same(log, { { "OnClick", "LeftButton", false }, { "OnClick", "RightButton", false } })
  end)
end

local function test_click_on_a_missing_name_throws_not_a_frame()
  withScenario("retail", function(s)
    local message = A.errors(function()
      s:click("NoSuchFrame")
    end, "click: not a frame")
    A.eq(message:find("attempt to index", 1, true), nil)
  end)
end

local function test_blocked_steps_throw_the_step_prefixed_reason()
  withScenario("retail", function(s)
    local b = _G.CreateFrame("Button", "StepBtn", _G.UIParent)
    local box = _G.CreateFrame("EditBox", "StepBox", _G.UIParent)
    b:Hide()
    A.errors(function()
      s:click("StepBtn")
    end, "click: hidden: StepBtn is not shown")
    b:Show()
    b:SetMouseMotionEnabled(false)
    A.errors(function()
      s:enter("StepBtn")
    end, "enter: mouse disabled")
    A.errors(function()
      s:type("StepBtn", "x")
    end, "type: not an EditBox")
    A.errors(function()
      s:press("StepBox", "ENTER")
    end, "press: StepBox does not have focus")
    box:Hide()
    A.errors(function()
      s:press("StepBox", "ENTER")
    end, "press: hidden: StepBox is not shown")
  end)
end

local function test_enter_and_leave_steps_move_the_mouse()
  withScenario("retail", function(s)
    local a = _G.CreateFrame("Button", nil, _G.UIParent)
    local b = _G.CreateFrame("Button", nil, _G.UIParent)
    local log = {}
    Rec.record(a, { "OnEnter", "OnLeave" }, log, "a")
    Rec.record(b, { "OnEnter", "OnLeave" }, log, "b")
    s:enter(a)
    s:enter(b)
    s:leave(b)
    local tags = {}
    for i, entry in ipairs(log) do
      tags[i] = entry[1]
    end
    A.same(tags, { "a:OnEnter", "a:OnLeave", "b:OnEnter", "b:OnLeave" })
    A.errors(function()
      s:leave(a)
    end, "does not have the mouse")
    A.errors(function()
      s:leave("NoSuchFrame")
    end, "leave: not a frame")
  end)
end

local function test_type_and_press_steps_drive_an_edit_box_by_name()
  withScenario("retail", function(s)
    local box = _G.CreateFrame("EditBox", "StepBox", _G.UIParent)
    local log = Rec.record(box, { "OnEnterPressed" })
    s:type("StepBox", "hi")
    A.eq(box:GetText(), "hi")
    s:press("StepBox", "ENTER")
    A.same(log, { { "OnEnterPressed" } })
  end)
end

local function test_blocked_step_fails_the_flavor_and_skips_later_steps()
  local reached = false
  local report = Scenario.matrix({ "retail" }, function(s)
    _G.CreateFrame("Frame", "Plain", _G.UIParent)
    s:click("Plain")
    reached = true
  end, HOVER).retail
  A.eq(report.status, "fail")
  A.eq(reached, false)
  A.contains(report.errors[1].message, "click: mouse disabled")
end

local function test_handler_error_in_a_click_is_recorded_and_the_step_goes_on()
  local postClicked = false
  local report = Scenario.matrix({ "retail" }, function(s)
    local b = _G.CreateFrame("Button", "BoomBtn", _G.UIParent)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function()
      error("boom")
    end)
    b:SetScript("PostClick", function()
      postClicked = true
    end)
    s:click("BoomBtn")
  end, HOVER).retail
  A.eq(report.status, "fail")
  A.eq(postClicked, true)
  local found = false
  for _, e in ipairs(report.errors) do
    found = found or tostring(e.message):find("boom", 1, true) ~= nil
  end
  A.eq(found, true)
end

local function test_scn_input_clicks_hovers_and_types_on_every_flavor()
  local result = Scenario.runFile(Clicky.INPUT_SCENARIO, { addon = "Clicky", root = Clicky.clickyCopy() })
  for _, flavor in ipairs(Flavors.list) do
    local report = result.results[flavor]
    A.eq(report.status, "pass", flavor)
    A.contains(report.notes, "log: " .. EXPECTED_LOG, flavor)
  end
end

return function()
  test_click_resolves_a_name_and_a_frame()
  test_click_on_a_missing_name_throws_not_a_frame()
  test_blocked_steps_throw_the_step_prefixed_reason()
  test_enter_and_leave_steps_move_the_mouse()
  test_type_and_press_steps_drive_an_edit_box_by_name()
  test_blocked_step_fails_the_flavor_and_skips_later_steps()
  test_handler_error_in_a_click_is_recorded_and_the_step_goes_on()
  test_scn_input_clicks_hovers_and_types_on_every_flavor()
end

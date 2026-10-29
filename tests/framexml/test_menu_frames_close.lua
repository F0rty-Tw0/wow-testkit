-- Menu frames: closing levels, the OnLeave and mouse focus a close leaves, and frames reused on reopen.
-- Split from test_menu_frames.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")
local MenuFrames = require("framexml.fakes.menu_frames")

local withFrameXML = HF.withFrameXML

local entry = HM.entry
local newLevel = HM.newLevel

local function test_close_hides_the_level_and_deeper_ones_and_clears_menus()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    MenuFrames.close(w, 2)
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(_G.DropDownList2:IsShown(), false)
    MenuFrames.close(w, 1)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

-- S3 (assumed): OnLeave on hide is from Blizzard's comments; the `false` motion argument is inferred.
local function test_close_fires_on_leave_without_motion_on_the_focused_entry_assumed()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local frame, leaves = level.entries[1].frame, {}
    frame:SetScript("OnLeave", function(_, motion)
      leaves[#leaves + 1] = motion
    end)
    Input.enter(w, frame)
    MenuFrames.close(w, 1)
    A.same(leaves, { false })
    A.eq(w.input.mouseFocus, nil)
  end)
end

local function test_close_survives_an_on_leave_that_closes_the_menus()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    local frame = second.entries[1].frame
    frame:SetScript("OnLeave", function()
      MenuFrames.close(w, 1)
    end)
    Input.enter(w, frame)
    MenuFrames.close(w, 1)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

-- The hovered entry's text is sized by its highlight font; an OnHide of the list that reads the rect caches it, so the
-- close has to drop the cached layout when it clears the focus, as Input.leave does.
local function test_close_drops_the_layout_of_the_hovered_entry()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local frame = level.entries[1].frame
    local normal, big = _G.CreateFont("MenuCloseSmall"), _G.CreateFont("MenuCloseBig")
    normal:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    big:SetFont("Fonts\\FRIZQT__.TTF", 30, "")
    frame:SetNormalFontObject(normal)
    frame:SetHighlightFontObject(big)
    frame:SetText("abc")
    frame:ClearAllPoints()
    frame:SetSize(200, 40)
    frame:SetPoint("CENTER", _G.UIParent)
    local text = frame:GetFontString()
    text:ClearAllPoints()
    text:SetPoint("CENTER")
    local small = text:GetWidth()
    Input.enter(w, frame)
    local hovered
    _G.DropDownList1:HookScript("OnHide", function()
      hovered = text:GetWidth()
    end)
    MenuFrames.close(w, 1)
    A.truthy(hovered > small)
    A.eq(text:GetWidth(), small)
  end)
end

local function test_close_leaves_focus_outside_the_level_alone()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local outside = _G.CreateFrame("Button", nil, _G.UIParent)
    Input.enter(w, outside)
    MenuFrames.close(w, 1)
    A.eq(w.input.mouseFocus, outside)
  end)
end

local function test_entering_another_entry_leaves_the_old_one_once()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "C") }, "DropDownList2")
    second.parentIndex = 1
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    local leaves = 0
    second.entries[1].frame:SetScript("OnLeave", function()
      leaves = leaves + 1
    end)
    Input.enter(w, second.entries[1].frame)
    Input.enter(w, first.entries[1].frame)
    A.eq(leaves, 1)
  end)
end

local function test_reopening_reuses_frames_and_hides_unused_ones()
  withFrameXML("retail", function(w)
    MenuFrames.open(w, 1, newLevel({ entry("button", "A"), entry("button", "B"), entry("button", "C") }, "DropDownList1"))
    local one, two = _G.DropDownList1Button1, _G.DropDownList1Button2
    MenuFrames.close(w, 1)
    MenuFrames.open(w, 1, newLevel({ entry("button", "Z") }, "DropDownList1"))
    A.eq(_G.DropDownList1Button1, one)
    A.eq(one.NormalText:GetText(), "Z")
    A.eq(one:IsShown(), true)
    A.eq(_G.DropDownList1Button2, two)
    A.eq(two:IsShown(), false)
  end)
end

return function()
  test_close_hides_the_level_and_deeper_ones_and_clears_menus()
  test_close_fires_on_leave_without_motion_on_the_focused_entry_assumed()
  test_close_survives_an_on_leave_that_closes_the_menus()
  test_close_drops_the_layout_of_the_hovered_entry()
  test_close_leaves_focus_outside_the_level_alone()
  test_entering_another_entry_leaves_the_old_one_once()
  test_reopening_reuses_frames_and_hides_unused_ones()
end

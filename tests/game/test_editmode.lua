-- Edit Mode layout reads and writes: C_EditMode answers from w.mock.editMode at call time. Every rule is assumed: no
-- source settles the preset count, what a save does to the mock or when an index is out of range.
local A = require("assert")
local G = require("tests.helpers.game")

local LAYOUT_A = { layoutName = "A", layoutType = 1, systems = {} }
local LAYOUT_B = { layoutName = "B", layoutType = 1, systems = {} }

-- Registers a frame that records each EDIT_MODE_LAYOUTS_UPDATED as { info, reconcile } and returns the list.
local function recordUpdates()
  local seen = {}
  local f = _G.CreateFrame("Frame")
  f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
  f:SetScript("OnEvent", function(_, _, info, reconcile)
    seen[#seen + 1] = { info = info, reconcile = reconcile }
  end)
  return seen
end

local function test_get_layouts_returns_the_mock_assumed()
  G.withGame("retail", function(w)
    w:setMock({ editMode = { layouts = { LAYOUT_A, LAYOUT_B }, active = 4 } })
    local info = _G.C_EditMode.GetLayouts()
    A.eq(info.activeLayout, 4)
    A.eq(#info.layouts, 2)
    A.eq(info.layouts[2].layoutName, "B")
  end)
end

local function test_get_layouts_answers_a_copy_assumed()
  G.withGame("retail", function(w)
    w:setMock({ editMode = { layouts = { LAYOUT_A }, active = 3 } })
    _G.C_EditMode.GetLayouts().layouts[1].layoutName = "changed"
    A.eq(_G.C_EditMode.GetLayouts().layouts[1].layoutName, "A")
  end)
end

local function test_save_layouts_stores_and_fires_updated_assumed()
  G.withGame("retail", function(w)
    local seen = recordUpdates()
    local saved = { layouts = { LAYOUT_B }, activeLayout = 3 }
    w:setMock({ editMode = { layouts = { LAYOUT_A, LAYOUT_B }, active = 4 } })
    _G.C_EditMode.SaveLayouts(saved)
    A.same(_G.C_EditMode.GetLayouts(), saved)
    A.eq(#seen, 1)
    A.same({ seen[1].info, seen[1].reconcile }, { saved, false })
  end)
end

local function test_set_active_layout_fires_and_ignores_bad_indexes_assumed()
  G.withGame("retail", function(w)
    local seen = recordUpdates()
    w:setMock({ editMode = { layouts = { LAYOUT_A, LAYOUT_B }, active = 3 } })
    _G.C_EditMode.SetActiveLayout(4)
    A.same({ #seen, _G.C_EditMode.GetLayouts().activeLayout }, { 1, 4 })
    _G.C_EditMode.SetActiveLayout(5)
    _G.C_EditMode.SetActiveLayout(0)
    A.same({ #seen, _G.C_EditMode.GetLayouts().activeLayout }, { 1, 4 })
    _G.C_EditMode.SetActiveLayout(1)
    A.same({ #seen, _G.C_EditMode.GetLayouts().activeLayout }, { 2, 1 })
  end)
end

local function test_layout_name_validity_assumed()
  G.withGame("retail", function()
    A.same({ _G.C_EditMode.IsValidLayoutName(""), _G.C_EditMode.IsValidLayoutName("   ") }, { false, false })
    A.eq(_G.C_EditMode.IsValidLayoutName("Raid"), true)
    A.same(_G.C_EditMode.GetAccountSettings(), {})
  end)
end

local function test_profile_strings_stay_unscripted_assumed()
  G.withGame("retail", function(w)
    _G.C_EditMode.ConvertLayoutInfoToString({})
    A.eq(w.unscripted["C_EditMode.ConvertLayoutInfoToString"], 1)
  end)
end

local function test_every_flavor_with_the_names_gets_them_assumed()
  G.withGame("vanilla", function(w)
    w:setMock({ editMode = { layouts = { LAYOUT_A }, active = 3 } })
    A.eq(_G.C_EditMode.GetLayouts().activeLayout, 3)
  end)
end

return function()
  test_get_layouts_returns_the_mock_assumed()
  test_get_layouts_answers_a_copy_assumed()
  test_save_layouts_stores_and_fires_updated_assumed()
  test_set_active_layout_fires_and_ignores_bad_indexes_assumed()
  test_layout_name_validity_assumed()
  test_profile_strings_stay_unscripted_assumed()
  test_every_flavor_with_the_names_gets_them_assumed()
end

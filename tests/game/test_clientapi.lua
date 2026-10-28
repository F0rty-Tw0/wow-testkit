-- Client APIs that Blizzard's own UI code calls while it loads (the real-extract loop of Task 10.2). Each test names the
-- Blizzard file that needed the call; answers are assumed unless a source is named.
local A = require("assert")
local AddonEnv = require("addon_env")
local G = require("tests.helpers.game")

-- Color.lua (Blizzard_SharedXMLBase) writes global names through GetCurrentEnvironment(): the one _G addon code sees.
local function test_get_current_environment_is_the_addon_global_table_assumed()
  G.withGame("retail", function(w)
    A.truthy(_G.GetCurrentEnvironment() == AddonEnv.global(w, "_G"), "the addon view of _G")
  end)
end

-- CurveConstants.lua (Blizzard_SharedXMLBase) builds four curves from C_CurveUtil.CreateCurve at load.
local function test_curve_object_evaluates_its_points_assumed()
  G.withGame("retail", function()
    local curve = _G.C_CurveUtil.CreateCurve()
    curve:SetType(_G.Enum.LuaCurveType.Linear)
    curve:AddPoint(0.0, 0)
    curve:AddPoint(1.0, 100)
    A.same({ curve:GetPointCount(), curve:Evaluate(0.25), curve:Evaluate(-1), curve:Evaluate(2) }, { 2, 25, 0, 100 })
    curve:SetType(_G.Enum.LuaCurveType.Step)
    A.same({ curve:GetType(), curve:Evaluate(0.5) }, { 1, 0 })
    curve:ClearPoints()
    A.eq(curve:GetPointCount(), 0)
  end)
end

-- ColorManager.lua (Blizzard_Colors) calls color:GenerateHexColorMarkup() on what C_ColorOverrides answers, so the
-- answer carries Blizzard's ColorMixin when that is loaded.
local function test_quality_colors_carry_the_color_mixin_assumed()
  G.withGame("retail", function(w)
    local plain = _G.C_ColorOverrides.GetColorForQuality(4)
    A.same({ plain.r, plain.g, plain.b, plain.a }, { 0.64, 0.21, 0.93, 1 })
    w:setGlobal("ColorMixin", {
      GetRGB = function(self)
        return self.r, self.g, self.b
      end,
    })
    A.same({ _G.C_ColorOverrides.GetColorForQuality(1):GetRGB() }, { 1, 1, 1 })
  end)
end

-- SecureTemplates.lua (Blizzard_FrameXML) starts with CopyTable(GetFrameMetatable().__index); a nil there aborted the
-- file and left SecureActionButtonMixin (CalculateAction) undefined for every Blizzard action button.
local function test_metatable_getters_answer_the_widget_class_metatable_assumed()
  G.withGame("retail", function()
    local frame = _G.CreateFrame("Frame")
    A.truthy(getmetatable(frame) == _G.GetFrameMetatable(), "Frame")
    A.truthy(getmetatable(_G.CreateFrame("Button")) == _G.GetButtonMetatable(), "Button")
    A.truthy(getmetatable(_G.CreateFrame("EditBox")) == _G.GetEditBoxMetatable(), "EditBox")
    A.truthy(getmetatable(frame:CreateFontString()) == _G.GetFontStringMetatable(), "FontString")
    A.eq(type(_G.GetFrameMetatable().__index.SetSize), "function")
  end)
end

-- SecureTemplates.lua (Blizzard_FrameXML) keys a table by the main hand and off-hand slot ids at load; a nil key
-- aborted the rest of the file.
local function test_inventory_slot_names_answer_their_ids_assumed()
  G.withGame("retail", function()
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("MainHandSlot"), 16)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("SecondaryHandSlot"), 17)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("HeadSlot"), 1)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("TabardSlot"), 19)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("NoSuchSlot"), nil)
  end)
end

return function()
  test_inventory_slot_names_answer_their_ids_assumed()
  test_metatable_getters_answer_the_widget_class_metatable_assumed()
  test_quality_colors_carry_the_color_mixin_assumed()
  test_curve_object_evaluates_its_points_assumed()
  test_get_current_environment_is_the_addon_global_table_assumed()
end

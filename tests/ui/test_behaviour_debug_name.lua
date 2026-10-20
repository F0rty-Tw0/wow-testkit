-- GetDebugName: the wiki API_Object_GetDebugName examples (row F3).
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function test_a_named_object_reports_its_name()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame", "SomeFrame")
    A.eq(f:GetDebugName(), "SomeFrame")
    A.eq(f:CreateTexture("SomeTexture"):GetDebugName(), "SomeTexture")
  end)
end

local function test_an_anonymous_frame_without_a_parent_reports_empty()
  withWidgets("retail", function()
    A.eq(_G.CreateFrame("Frame"):GetDebugName(), "")
  end)
end

local function test_an_anonymous_child_under_a_parent_key_reports_parent_dot_key()
  withWidgets("vanilla", function()
    local parent = _G.CreateFrame("Frame", "CharacterFrame")
    parent.b = _G.CreateFrame("Frame")
    A.eq(parent.b:GetDebugName(), "")
    parent.b:SetParent(parent)
    A.eq(parent.b:GetDebugName(), "CharacterFrame.b")
  end)
end

-- The client prints the object's memory address ("SomeFrame.156f1390860"); the kit's is its table's address.
local function test_an_anonymous_child_without_a_key_reports_parent_dot_address_assumed()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame", "SomeFrame")
    local name = f:CreateTexture():GetDebugName()
    A.truthy(name:find("^SomeFrame%.[1-9a-f]%x*$"), name)
  end)
end

return function()
  test_a_named_object_reports_its_name()
  test_an_anonymous_frame_without_a_parent_reports_empty()
  test_an_anonymous_child_under_a_parent_key_reports_parent_dot_key()
  test_an_anonymous_child_without_a_key_reports_parent_dot_address_assumed()
end

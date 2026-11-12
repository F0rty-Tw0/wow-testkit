-- SetParentKey, GetParentKey, ClearParentKey: the parent's field that holds the object (row F10).
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

-- source: forever 70862 blizzard_compactraidframemanager.lua:123-136 parents a pooled button, then
-- SetParentKey("raidMarker"..i), and :858-859 reads raidMarkers["raidMarker"..i].
local function test_set_parent_key_puts_the_object_on_its_parent()
  for _, flavor in ipairs({ "forever", "tbc" }) do
    withWidgets(flavor, function()
      local parent = _G.CreateFrame("Frame")
      local button = _G.CreateFrame("Button")
      button:SetParent(parent)
      button:SetParentKey("raidMarker1")
      A.eq(parent.raidMarker1, button, flavor)
      A.eq(button:GetParentKey(), "raidMarker1", flavor)
    end)
  end
end

local function test_clear_other_keys_removes_the_old_key_assumed()
  withWidgets("forever", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    child:SetParentKey("old")
    child:SetParentKey("new", true)
    A.same({ parent.old, parent.new }, { nil, child })
  end)
end

local function test_clear_parent_key_removes_the_field_assumed()
  withWidgets("forever", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    child:SetParentKey("slot")
    child:ClearParentKey()
    A.same({ parent.slot, child:GetParentKey() }, { nil, nil })
  end)
end

return function()
  test_set_parent_key_puts_the_object_on_its_parent()
  test_clear_other_keys_removes_the_old_key_assumed()
  test_clear_parent_key_removes_the_field_assumed()
end

-- Menu pick step: which entries s:pick enters and clicks through, and what it treats as a click.
local A = require("assert")
local HMS = require("tests.helpers.menu_scenario")

local withMenuScenario = HMS.withMenuScenario

-- F3: a hook on a list button whose OnClick was cleared becomes its handler, so pick clicks it.
local function test_pick_clicks_a_list_button_whose_only_click_is_a_hook()
  withMenuScenario(function(s)
    local dd = _G.CreateFrame("Frame", "HookPickDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function()
      _G.UIDropDownMenu_AddButton({ text = "A1", notCheckable = true }, 1)
    end)
    _G.ToggleDropDownMenu(1, nil, dd)
    local hooked = 0
    _G.DropDownList1Button1:SetScript("OnClick", nil)
    _G.DropDownList1Button1:HookScript("OnClick", function()
      hooked = hooked + 1
    end)
    s:pick("A1")
    A.eq(hooked, 1)
  end)
end

return function()
  test_pick_clicks_a_list_button_whose_only_click_is_a_hook()
end

-- Kit fakes carry taint (inventory F): the dropdown globals and the tooltip's unit APIs taint Blizzard code that reads an
-- addon's value, and Menu / TooltipDataProcessor callbacks run with their owner's taint. Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")

local PLAYER = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80, guid = "G" }

local function test_tainted_dropdown_global_taints_blizzard_dropdown_code_assumed() -- TS4
  HF.withFrameXML("retail", function(w)
    local Taint = require("taint")
    H.run(w, "Foo", "UIDROPDOWNMENU_OPEN_MENU = 1")
    local frame = _G.CreateFrame("Frame", "TKDD", _G.UIParent, "UIDropDownMenuTemplate")
    local seen
    w:run("blizzard", function()
      _G.UIDropDownMenu_Initialize(frame, function()
        seen = Taint.current(w)
      end)
    end)
    A.eq(seen, "Foo")
    A.eq(H.events(w, "read")[1].name, "UIDROPDOWNMENU_OPEN_MENU")
  end)
end

local function test_menu_and_tooltip_hooks_run_with_their_owner_taint()
  HF.withUnits("retail", function(w)
    H.probe(w, require("taint"))
    w:unit("mouseover", PLAYER)
    H.run(w, "Foo", "Menu.ModifyMenu('MENU_X', function() menuSeen = TK_Seen() end)")
    H.run(w, "Foo", "TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function() tipSeen = TK_Seen() end)")
    _G.MenuUtil.CreateContextMenu(HM.owner(), function(_, root)
      root:SetTag("MENU_X", {})
      root:CreateButton("Own", function() end)
    end)
    w:run("blizzard", function()
      _G.GameTooltip:SetUnit("mouseover")
    end)
    A.same({ _G.menuSeen, _G.tipSeen }, { "Foo", "Foo" })
  end)
end

local function test_replaced_unit_api_taints_the_tooltip_build_assumed() -- TS4
  HF.withUnits("retail", function(w)
    w:unit("mouseover", PLAYER)
    H.run(w, "Foo", "UnitName = function() return 'x' end")
    w:run("blizzard", function()
      _G.GameTooltip:SetUnit("mouseover")
    end)
    local read = H.events(w, "read")[1]
    A.same({ read.name, read.addon }, { "UnitName", "Foo" })
  end)
end

return function()
  test_tainted_dropdown_global_taints_blizzard_dropdown_code_assumed()
  test_menu_and_tooltip_hooks_run_with_their_owner_taint()
  test_replaced_unit_api_taints_the_tooltip_build_assumed()
end

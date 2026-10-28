-- The merchant window (Task 12.5): the opener writes the stock store and the window reads it back through the merchant
-- reads. The plan lists this test in test_blizzard_windows.lua, which is at its 300-line limit, so it lives here. The
-- extract is a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local BlizzardWindows = require("blizzard_windows")
local W = require("tests.helpers.windows")

local SPEC = { merchant = { addon = "Blizzard_MiniMerchant", open = "MERCHANT_SHOW", frame = "MiniMerchantFrame" } }
local STOCK = { items = { { itemID = 6948, name = "Kit Stone", texture = 134414, price = 100 } } }

local function test_merchant_window_shows_the_stock()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SPEC
    end,
  }, function(s)
    s:openWindow("merchant", STOCK)
    A.same({ _G.MiniMerchantFrame:IsShown(), _G.MiniMerchantFrame.Row:GetText() }, { true, "Kit Stone" })
    s:closeWindow("merchant")
    A.eq(_G.GetMerchantNumItems(), 1) -- closing keeps the store
  end)
end

-- (BU16) the classic merchant's XML OnLoad calls SmallMoneyFrame_OnLoad (TBC\MerchantFrame.xml:71) and Blizzard_MoneyFrame is no
-- dependency of Blizzard_UIPanels_Game's classic TOC; its own TOC has no LoadOnDemand line, so it loads before the targets.
local function test_classic_layer_loads_the_money_frame_addon_first()
  local addons = { "Blizzard_MoneyFrame", "Blizzard_UIPanels_Game" }
  for _, flavor in ipairs({ "tbc", "vanilla", "mists" }) do
    W.withWindows(flavor, { addons = addons }, function(w)
      A.same({ BlizzardWindows.first(w), BlizzardWindows.startup(w) }, { { "Blizzard_MoneyFrame" }, { "Blizzard_UIPanels_Game" } }, flavor)
    end)
  end
  W.withWindows("retail", { addons = addons }, function(w) -- retail's TOC lists it as a dependency instead
    A.same({ BlizzardWindows.first(w), BlizzardWindows.startup(w) }, { {}, { "Blizzard_UIPanels_Game" } })
  end)
end

local ORDER = {
  blizzard_moneyframe = { toc = "## Interface: 20506\nMoney.lua\n", files = { ["money.lua"] = 'MiniOrder = (MiniOrder or "") .. "money,"' } },
  blizzard_actionbar = { toc = "## Interface: 20506\nBar.lua\n", files = { ["bar.lua"] = 'MiniOrder = (MiniOrder or "") .. "bar,"' } },
}
local function test_money_frame_loads_before_the_default_targets()
  B.run(B.mini(ORDER), { flavor = "tbc", header = "Interface-TBC: 20506" }, function()
    A.eq(_G.MiniOrder, "money,bar,")
  end)
end

-- (BU17, assumed) the classic panel manager reads UIParent's attributes (UIParentPanelManager.lua:586), which UIParent.xml
-- sets and the layer never loads; opening a window sets them from the extract's file.
local UIPARENT = {
  blizzard_uiparent = {
    toc = "## Interface: 20506\n",
    files = {
      ["classic/uiparent.xml"] = [[<Ui><Frame name="UIParent"><Attributes>
<Attribute name="TOP_OFFSET" type="number" value="-7"/><Attribute name="LEFT_OFFSET" type="number" value="5"/>
<Attribute name="Kit_Flag" type="boolean" value="true"/></Attributes></Frame></Ui>]],
    },
  },
}
local function test_opening_a_classic_window_sets_the_uiparent_attributes_assumed()
  B.run(B.mini(UIPARENT), {
    flavor = "tbc",
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SPEC
    end,
  }, function(s)
    A.eq(_G.UIParent:GetAttribute("TOP_OFFSET"), nil)
    s:openWindow("merchant", STOCK)
    A.same({ _G.UIParent:GetAttribute("TOP_OFFSET"), _G.UIParent:GetAttribute("LEFT_OFFSET"), _G.UIParent:GetAttribute("Kit_Flag") }, { -7, 5, true })
  end)
  B.run(B.mini(UIPARENT), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SPEC
    end,
  }, function(s)
    s:openWindow("merchant", STOCK)
    A.eq(_G.UIParent:GetAttribute("TOP_OFFSET"), nil) -- retail lays its panels out through UIPanelLayoutFrame
  end)
end

return function()
  test_merchant_window_shows_the_stock()
  test_classic_layer_loads_the_money_frame_addon_first()
  test_money_frame_loads_before_the_default_targets()
  test_opening_a_classic_window_sets_the_uiparent_attributes_assumed()
end

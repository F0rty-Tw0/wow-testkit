-- SecureActionButton and SecureUnitButton: the attribute lookup order, the unit, the action types and the global each calls,
-- and who may click. Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")

local function actionButton(name, template)
  local b = _G.CreateFrame("Button", name, _G.UIParent, template or "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp")
  return b
end

local function recorder(w, name)
  local calls = {}
  w:stub(name, function(...)
    calls[#calls + 1] = { ... }
  end)
  return calls
end

local function test_hardware_click_casts_but_an_addon_click_is_blocked() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    local b = actionButton("TKAct")
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", "Kit Strike")
    b:SetAttribute("unit", "target")
    local cast = recorder(w, "CastSpellByName")
    s:click(b)
    A.same(cast, { { "Kit Strike", "target" } })
    H.run(w, "Foo", "TKAct:Click()")
    A.eq(#cast, 1) -- the second call never reached the stub
    A.eq(w.taint.log[#w.taint.log].event, "ADDON_ACTION_FORBIDDEN")
  end)
end

local function test_modifier_prefix_and_button_suffix_pick_the_attribute() -- TS14
  H.withTaint("retail", function(w)
    local b = actionButton("TKAct2")
    b:SetAttribute("type1", "spell")
    b:SetAttribute("shift-type1", "macro")
    b:SetAttribute("*type2", "item")
    A.eq(_G.SecureButton_GetModifiedAttribute(b, "type", "LeftButton"), "spell")
    w:setMock({ modifiers = { shift = true } })
    A.eq(_G.SecureButton_GetModifiedAttribute(b, "type", "LeftButton"), "macro")
    A.eq(_G.SecureButton_GetModifiedAttribute(b, "type", "RightButton"), "item")
    A.same({ _G.SecureButton_GetButtonSuffix("MiddleButton"), _G.SecureButton_GetButtonSuffix("Button7") }, { "3", "7" })
    A.same({ _G.SecureButton_GetButtonSuffix("Extra"), _G.SecureButton_GetButtonSuffix(nil) }, { "-Extra", "" })
    w:setMock({ modifiers = { alt = true, ctrl = true, shift = true } })
    A.eq(_G.SecureButton_GetModifierPrefix(b), "alt-ctrl-shift-")
  end)
end

local function test_attribute_lookup_tries_the_five_names_in_order() -- TS14
  H.withTaint("retail", function()
    local b = actionButton("TKAct3")
    b:SetAttribute("type", "plain")
    A.eq(b:GetAttribute("shift-", "type", "1"), "plain")
    b:SetAttribute("*type*", "wild")
    A.eq(b:GetAttribute("shift-", "type", "1"), "wild")
    b:SetAttribute("shift-type*", "shiftwild")
    A.eq(b:GetAttribute("shift-", "type", "1"), "shiftwild")
    b:SetAttribute("*type1", "anymod")
    A.eq(b:GetAttribute("shift-", "type", "1"), "anymod")
    b:SetAttribute("shift-type1", "exact")
    A.eq(b:GetAttribute("shift-", "type", "1"), "exact")
    A.eq(b:GetAttribute("type"), "plain") -- one argument is the plain lookup
  end)
end

local function test_noop_value_and_useparent_pick_the_attribute() -- TS14
  H.withTaint("retail", function()
    local parent = actionButton("TKActParent")
    local child = _G.CreateFrame("Button", "TKActChild", parent, "SecureActionButtonTemplate")
    parent:SetAttribute("type", "target")
    A.eq(_G.SecureButton_GetModifiedAttribute(child, "type", "LeftButton"), nil)
    child:SetAttribute("useparent-type", true)
    A.eq(_G.SecureButton_GetModifiedAttribute(child, "type", "LeftButton"), "target")
    child:SetAttribute("*type*", "")
    child:SetAttribute("shift-type1", "")
    A.eq(_G.SecureButton_GetModifiedAttribute(child, "type", "LeftButton", "shift-", "1"), nil) -- "" is ATTRIBUTE_NOOP
  end)
end

local CASES = {
  { type = "spell", attrs = { spell = "Kit Strike" }, stub = "CastSpellByName", args = { "Kit Strike", "target" } },
  { type = "spell", attrs = { spell = "1234" }, stub = "CastSpellByID", args = { 1234, "target" } },
  { type = "item", attrs = { item = "Kit Potion" }, global = "SecureCmdUseItem", args = { "Kit Potion", nil, nil, "target" }, n = 4 },
  { type = "macro", attrs = { macro = "KitMacro" }, stub = "RunMacro", args = { "KitMacro", "LeftButton" } },
  { type = "macro", attrs = { macrotext = "/kit" }, stub = "C_Macro.RunMacroText", args = { "/kit", "LeftButton" } },
  { type = "target", attrs = {}, stub = "TargetUnit", args = { "target" } },
  { type = "focus", attrs = {}, stub = "FocusUnit", args = { "target" } },
  { type = "assist", attrs = {}, stub = "AssistUnit", args = { "target" } },
  { type = "cancelaura", attrs = { spell = "Kit Aura" }, stub = "CancelSpellByName", args = { "Kit Aura" } },
}

local function test_each_action_type_calls_its_global() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    for i, case in ipairs(CASES) do
      local b = actionButton("TKActType" .. i)
      b:SetAttribute("type", case.type)
      b:SetAttribute("unit", "target")
      for name, value in pairs(case.attrs) do
        b:SetAttribute(name, value)
      end
      local calls = {}
      local function spy(...)
        calls[#calls + 1] = { n = select("#", ...), ... }
      end
      if case.stub then
        w:stub(case.stub, spy)
      else
        w:setGlobal(case.global, spy)
      end
      s:click(b)
      local n = case.n or #case.args
      A.eq(#calls, 1, case.type .. " " .. tostring(case.stub or case.global))
      A.same(calls[1], { n = n, unpack(case.args, 1, n) }, case.type)
    end
  end)
end

local function test_unmodelled_type_counts_unscripted_and_does_nothing() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    local b = actionButton("TKActMenu")
    b:SetAttribute("type", "togglemenu")
    b:SetAttribute("unit", "target")
    s:click(b)
    A.eq(w.unscripted["secure:togglemenu"], 1)
  end)
end

local function test_missing_global_counts_unscripted_and_does_nothing() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    w:setGlobal("UseToy", nil)
    local b = actionButton("TKActToy")
    b:SetAttribute("type", "toy")
    b:SetAttribute("toy", "12")
    s:click(b)
    A.eq(w.unscripted["secure:toy"], 1)
    A.eq(#w.errors, 0)
  end)
end

local function test_custom_type_runs_its_function_after_forceinsecure() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    local b = actionButton("TKActCustom")
    local seen
    b:SetAttribute("type", "kit")
    b:SetAttribute("unit", "target")
    b.kit = function(self, unit, button, isKeyPress, down)
      seen = { self == b, unit, button, isKeyPress, down, _G.issecure() }
    end
    s:click(b)
    A.same(seen, { true, "target", "LeftButton", false, false, false })
  end)
end

local function test_unit_attribute_resolution_assumed() -- TS14
  H.withTaint("retail", function()
    local b = actionButton("TKActUnit")
    A.eq(_G.SecureButton_GetUnit(b), nil)
    b:SetAttribute("unit", "raid1")
    b:SetAttribute("unitsuffix", "pet")
    A.eq(_G.SecureButton_GetUnit(b), "raidpet1") -- raid1pet is mapped to raidpet1
    A.eq(_G.SecureButton_GetModifiedUnit(b, "LeftButton"), "raidpet1")
    b:SetAttribute("unit", "player")
    A.eq(_G.SecureButton_GetModifiedUnit(b, "LeftButton"), "pet") -- playerpet is pet
    b:SetAttribute("*unit2", "focus")
    A.eq(_G.SecureButton_GetModifiedUnit(b, "RightButton"), "focuspet")
  end)
end

local function test_click_on_a_missing_unit_does_nothing() -- TS14
  H.withTaint("retail", function(w, _, s)
    local b = actionButton("TKActNoUnit")
    b:SetAttribute("type", "target")
    b:SetAttribute("unit", "target")
    local calls = recorder(w, "TargetUnit")
    s:click(b)
    A.eq(#calls, 0) -- no such unit
    local clears = recorder(w, "ClearTarget")
    b:SetAttribute("unit", "none")
    s:click(b)
    A.eq(#calls, 0)
    A.eq(#clears, 1) -- "none" clears the target
  end)
end

local function test_harmbutton_remaps_the_button_for_an_attackable_unit() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    w:stub("UnitCanAttack", { returns = { true } })
    local b = actionButton("TKActHarm")
    b:SetAttribute("unit", "target")
    b:SetAttribute("harmbutton1", "nuke")
    b:SetAttribute("type-nuke", "spell")
    b:SetAttribute("spell-nuke", "Kit Bolt")
    b:SetAttribute("type1", "target")
    local cast = recorder(w, "CastSpellByName")
    s:click(b)
    A.same(cast, { { "Kit Bolt", "target" } })
  end)
end

local function test_secure_unit_button_defaults_assumed() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("player", { name = "Kit Player" })
    local b = _G.CreateFrame("Button", "TKUnit", _G.UIParent, "SecureUnitButtonTemplate")
    A.eq(w.ui.state[b].protected, true)
    A.same({ b:GetAttribute("*type1"), b:GetAttribute("unit") }, {}) -- the template does not call SecureUnitButton_OnLoad
    _G.SecureUnitButton_OnLoad(b, "player", "kitmenu")
    A.same(
      { b:GetAttribute("*type1"), b:GetAttribute("*type2"), b:GetAttribute("unit"), b:GetAttribute("menu-function") },
      { "target", "menu", "player", "kitmenu" }
    )
    local calls = recorder(w, "TargetUnit")
    s:click(b)
    A.same(calls, { { "player" } })
  end)
end

local function test_click_on_disabled_or_unregistered_button_does_nothing() -- TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    local b = actionButton("TKActOff")
    b:SetAttribute("type", "target")
    b:SetAttribute("unit", "target")
    local calls = recorder(w, "TargetUnit")
    b:Disable()
    A.errors(function()
      s:click(b)
    end, "disabled")
    b:Click()
    A.eq(#calls, 0)
    b:Enable()
    b:RegisterForClicks("RightButtonUp")
    A.errors(function()
      s:click(b)
    end, "not registered")
    A.eq(#calls, 0)
  end)
end

local function test_addon_click_follows_use_on_key_down_assumed() -- TS14
  H.withTaint("retail", function(w, _, s)
    local b = actionButton("TKActKey")
    local n, lastDown = 0, nil
    b:SetAttribute("type", "kit")
    b.kit = function(_, _, _, _, down)
      n, lastDown = n + 1, down
    end
    b:SetAttribute("useOnKeyDown", true)
    b:RegisterForClicks("AnyUp", "AnyDown")
    s:click(b)
    A.eq(n, 1)
    A.eq(lastDown, false) -- a hardware (secure) mouse click acts on the up event whatever useOnKeyDown says
    local function addonClick(down)
      H.run(w, "Foo", "TKActKey:Click('LeftButton', " .. tostring(down) .. ")")
    end
    addonClick(false)
    A.eq(n, 1) -- a click from addon code is a key press: with useOnKeyDown it acts on the down event only
    addonClick(true)
    A.eq(n, 2)
    b:SetAttribute("useOnKeyDown", nil)
    _G.SetCVar("ActionButtonUseKeyDown", 1) -- the CVar decides when the attribute is unset
    addonClick(false)
    A.eq(n, 2)
    addonClick(true)
    A.eq(n, 3)
    _G.SetCVar("ActionButtonUseKeyDown", 0)
    addonClick(true)
    addonClick(false)
    A.eq(n, 4) -- without it the up event acts
  end)
end

local function test_a_click_reading_an_addon_replaced_action_global_runs_it_tainted_assumed() -- TS4, TS14
  H.withTaint("retail", function(w, _, s)
    w:unit("target", { name = "Kit Dummy" })
    local b = actionButton("TKActRep")
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", "Kit Strike")
    b:SetAttribute("unit", "target")
    local cast = recorder(w, "CastSpellByName")
    H.run(w, "Foo", "local orig = CastSpellByName; CastSpellByName = function(...) TK_Sec = issecure(); orig(...) end")
    s:click(b)
    A.same({ _G.TK_Sec, #cast, #H.events(w, "blocked") }, { false, 0, 1 })
  end)
end

return function()
  test_hardware_click_casts_but_an_addon_click_is_blocked()
  test_modifier_prefix_and_button_suffix_pick_the_attribute()
  test_attribute_lookup_tries_the_five_names_in_order()
  test_noop_value_and_useparent_pick_the_attribute()
  test_each_action_type_calls_its_global()
  test_unmodelled_type_counts_unscripted_and_does_nothing()
  test_missing_global_counts_unscripted_and_does_nothing()
  test_custom_type_runs_its_function_after_forceinsecure()
  test_unit_attribute_resolution_assumed()
  test_click_on_a_missing_unit_does_nothing()
  test_harmbutton_remaps_the_button_for_an_attackable_unit()
  test_secure_unit_button_defaults_assumed()
  test_click_on_disabled_or_unregistered_button_does_nothing()
  test_addon_click_follows_use_on_key_down_assumed()
  test_a_click_reading_an_addon_replaced_action_global_runs_it_tainted_assumed()
end

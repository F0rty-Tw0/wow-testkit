-- SecureHandler templates, snippets in the restricted environment, Execute, frame references and WrapScript. Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")
local SecureEnv = require("secure_env")

local COMBAT_ERROR = "Cannot use SecureHandlers API during combat"

local function handler(name, template)
  local f = _G.CreateFrame("Button", name, _G.UIParent, template or "SecureHandlerClickTemplate")
  f:RegisterForClicks("AnyUp")
  return f
end

local function hiddenTarget(name)
  local target = _G.CreateFrame("Frame", name, _G.UIParent, "SecureFrameTemplate")
  target:Hide()
  return target
end

local function lastError(w)
  return tostring(w.errors[#w.errors] and w.errors[#w.errors].message)
end

local function test_click_snippet_shows_a_protected_frame_in_combat() -- TS15
  -- securehandlers.lua:435-438 refuses Execute (API_OnAttributeChanged) in combat even for secure code, so the in-combat
  -- path is a hardware click on a SecureHandlerClickTemplate whose _onclick snippet runs secure.
  H.withTaint("retail", function(w, _, s)
    local h = handler("TKH")
    local target = hiddenTarget("TKT")
    h:SetFrameRef("p", target)
    h:SetAttribute("_onclick", "self:GetFrameRef('p'):Show()")
    H.setCombat(w, true)
    s:click(h)
    A.eq(target:IsShown(), true)
    target:Hide()
    H.run(w, "Foo", "SecureHandlerExecute(TKH, 'self:GetFrameRef(\"p\"):Show()')")
    A.eq(target:IsShown(), false) -- tainted Execute in combat is refused (TS15)
    A.contains(lastError(w), COMBAT_ERROR)
  end)
end

local function test_handler_api_is_refused_in_combat_for_every_caller() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHApi", "SecureHandlerBaseTemplate")
    local other = hiddenTarget("TKHApiOther")
    H.setCombat(w, true)
    w:run("blizzard", function()
      A.errors(function()
        h:Execute("x = 1")
      end, COMBAT_ERROR)
      A.errors(function()
        h:SetFrameRef("p", other)
      end, COMBAT_ERROR)
      A.errors(function()
        h:WrapScript(other, "OnShow", "x = 1")
      end, COMBAT_ERROR)
      A.errors(function()
        h:UnwrapScript(other, "OnShow")
      end, COMBAT_ERROR)
      A.errors(function()
        _G.SecureHandlerExecute(h, "x = 1")
      end, COMBAT_ERROR)
    end)
  end)
end

local function test_execute_runs_secure_for_tainted_callers_out_of_combat() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHExec", "SecureHandlerBaseTemplate")
    local target = hiddenTarget("TKHExecT")
    h:SetFrameRef("p", target)
    H.run(w, "Foo", "TKHExec:Execute(\"self:GetFrameRef('p'):Show()\")")
    A.eq(target:IsShown(), true)
    A.eq(#w.errors, 0)
  end)
end

local function test_execute_checks_its_header_and_body() -- TS15
  H.withTaint("retail", function()
    local plain = _G.CreateFrame("Frame", "TKHPlain", _G.UIParent)
    A.errors(function()
      _G.SecureHandlerExecute(plain, "x = 1")
    end, "Header frame must be explicitly protected")
    local h = handler("TKHChk", "SecureHandlerBaseTemplate")
    A.errors(function()
      h:Execute(1)
    end, "Invalid body")
    A.errors(function()
      _G.SecureHandlerExecute({}, "x = 1")
    end, "Invalid header frame")
  end)
end

local function test_a_tainted_click_cannot_run_a_snippet() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHTaint")
    local target = hiddenTarget("TKHTaintT")
    h:SetFrameRef("p", target)
    h:SetAttribute("_onclick", "self:GetFrameRef('p'):Show()")
    H.run(w, "Foo", "TKHTaint:Click()")
    A.eq(target:IsShown(), false)
    A.contains(lastError(w), "Cannot call restricted closure from insecure code")
  end)
end

local function test_a_tainted_click_in_combat_changes_no_protected_frame() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHCTaint")
    local target = hiddenTarget("TKHCTaintT")
    h:SetFrameRef("p", target)
    h:SetAttribute("_onclick", "self:GetFrameRef('p'):Show()")
    H.setCombat(w, true)
    H.run(w, "Foo", "TKHCTaint:Click()")
    A.eq(target:IsShown(), false)
    A.contains(lastError(w), "Cannot call restricted closure from insecure code")
  end)
end

local function test_a_tainted_state_attribute_runs_the_onstate_snippet_assumed() -- TS15
  H.withTaint("retail", function(w)
    local g = _G.CreateFrame("Frame", "TKHTState", _G.UIParent, "SecureHandlerStateTemplate")
    g:SetAttribute("_onstate-page", "self:SetAttribute('page', newstate)")
    local a = _G.CreateFrame("Frame", "TKHTAttr", _G.UIParent, "SecureHandlerAttributeTemplate")
    a:SetAttribute("_onattributechanged", "if name == 'x' then self:SetAttribute('seen', value) end")
    H.run(w, "Foo", "TKHTState:SetAttribute('state-page', 3); TKHTAttr:SetAttribute('x', 5)")
    A.same({ g:GetAttribute("page"), a:GetAttribute("seen"), #w.errors }, { 3, 5, 0 })
  end)
end

-- The client's behaviour, not a regression: only the attribute-set route runs a snippet secure for tainted callers.
local function test_a_tainted_show_errors_in_the_onshow_snippet_as_the_client_does() -- TS15
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Frame", "TKHTShow", _G.UIParent, "SecureHandlerShowHideTemplate")
    f:Hide()
    f:SetAttribute("_onshow", "self:SetAttribute('shown', 1)")
    H.run(w, "Foo", "TKHTShow:Show()")
    A.same({ f:IsShown(), f:GetAttribute("shown") }, { true, nil })
    A.contains(lastError(w), "Cannot call restricted closure from insecure code")
  end)
end

local function test_a_tainted_state_attribute_in_combat_is_blocked_before_the_snippet() -- TS9, TS15
  H.withTaint("retail", function(w)
    local g = _G.CreateFrame("Frame", "TKHCState", _G.UIParent, "SecureHandlerStateTemplate")
    g:SetAttribute("_onstate-page", "self:SetAttribute('page', newstate)")
    H.setCombat(w, true)
    H.run(w, "Foo", "TKHCState:SetAttribute('state-page', 3)")
    A.same({ g:GetAttribute("state-page"), g:GetAttribute("page"), #w.errors }, { nil, nil, 0 })
    A.eq(H.events(w, "blocked")[1].name, "TKHCState:SetAttribute()")
  end)
end

local function test_restricted_environment_hides_globals() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHEnv", "SecureHandlerBaseTemplate")
    local r = SecureEnv.run(w, h, "return _G, CreateFrame, io, require, strlen('abc'), type(newtable()), floor(2.5), rawtype(self)")
    A.same({ r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }, { true, nil, nil, nil, nil, 3, "table", 2, "table" })
    r = SecureEnv.run(w, h, "return self:GetName(), control:GetName(), select('#', pairs(newtable()))")
    A.same({ r[1], r[2], r[3], r[4] }, { true, "TKHEnv", "TKHEnv", 3 })
  end)
end

local function test_a_snippet_calling_an_addon_replaced_global_runs_it_tainted_assumed() -- TS4
  H.withTaint("retail", function(w)
    handler("TKHFwd", "SecureHandlerBaseTemplate")
    local cast = 0
    w:stub("CastSpellByName", function()
      cast = cast + 1
    end)
    H.run(w, "Foo", "UnitExists = function() TK_Sec = issecure(); CastSpellByName('Fireball'); return true end")
    H.run(w, "Foo", "SecureHandlerExecute(TKHFwd, \"UnitExists('target')\")")
    A.same({ _G.TK_Sec, cast, #H.events(w, "blocked") }, { false, 0, 1 })
  end)
end

local function test_a_snippet_calling_an_addon_replaced_namespace_function_runs_it_tainted_assumed() -- TS4
  H.withTaint("retail", function(w)
    handler("TKHNs", "SecureHandlerBaseTemplate")
    local cast = 0
    w:stub("CastSpellByName", function()
      cast = cast + 1
    end)
    H.run(w, "Foo", "C_ActionBar.GetActionBarPage = function() TK_Sec = issecure(); CastSpellByName('Fireball'); return 1 end")
    H.run(w, "Foo", "SecureHandlerExecute(TKHNs, 'GetActionBarPage()')")
    local blocked = H.events(w, "blocked")
    A.same({ _G.TK_Sec, cast, #blocked, blocked[1] and blocked[1].addon }, { false, 0, 1, "Foo" })
  end)
end

local function test_a_handle_calls_the_class_method_not_an_addon_field() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHMeth", "SecureHandlerBaseTemplate")
    h:Hide()
    H.run(w, "Foo", "TKHMeth.Show = function() TK_Called = true end")
    H.run(w, "Foo", "SecureHandlerExecute(TKHMeth, 'self:Show()')")
    A.same({ _G.TK_Called, h:IsShown(), #w.errors }, { nil, true, 0 })
  end)
end

local function test_a_handle_ignores_an_addon_edit_of_the_class_method_table() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHMeta", "SecureHandlerBaseTemplate")
    h:Hide()
    H.run(w, "Foo", "getmetatable(TKHMeta).__index.Show = function() TK_Called = true end")
    H.run(w, "Foo", "SecureHandlerExecute(TKHMeta, 'self:Show()')")
    A.same({ _G.TK_Called, h:IsShown(), #w.errors }, { nil, true, 0 })
  end)
end

local function test_snippet_globals_ignore_an_addon_replacement_made_before_the_first_snippet() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHBase", "SecureHandlerBaseTemplate")
    H.run(w, "Foo", "strsplit = function() TK_Called = true end")
    local r = SecureEnv.run(w, h, "return strsplit(',', 'a,b')")
    A.same({ r[2], r[3], _G.TK_Called }, { "a", "b", nil })
  end)
end

local function test_snippets_see_a_string_name_the_kit_only_stubs() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHUtf", "SecureHandlerBaseTemplate")
    local r = SecureEnv.run(w, h, "return strcmputf8i('a', 'A')")
    A.same({ r[1], r.n, #w.errors }, { true, select("#", _G.strcmputf8i("a", "A")) + 1, 0 })
    A.eq(w.unscripted["strcmputf8i"], 2)
  end)
end

local function test_snippets_refuse_function_and_table_syntax() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHSyn", "SecureHandlerBaseTemplate")
    local r = SecureEnv.run(w, h, "x = function() end")
    A.eq(r[1], false)
    A.contains(lastError(w), "The function keyword is not permitted")
    r = SecureEnv.run(w, h, "x = { }")
    A.eq(r[1], false)
    A.contains(lastError(w), "Direct table creation is not permitted")
  end)
end

local function test_environment_variables_persist_per_header() -- TS15
  H.withTaint("retail", function(w)
    local a, b = handler("TKHPerA", "SecureHandlerBaseTemplate"), handler("TKHPerB", "SecureHandlerBaseTemplate")
    SecureEnv.run(w, a, "count = (count or 0) + 1")
    SecureEnv.run(w, a, "count = (count or 0) + 1")
    A.eq(SecureEnv.run(w, a, "return count")[2], 2)
    A.eq(SecureEnv.run(w, b, "return count")[2], nil)
  end)
end

local function test_attribute_template_runs__onattributechanged_snippet() -- TS15
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Frame", "TKHAttr", _G.UIParent, "SecureHandlerAttributeTemplate")
    f:SetAttribute("_onattributechanged", "if name == 'x' then self:SetAttribute('y', value) end")
    f:SetAttribute("x", 1)
    A.eq(f:GetAttribute("y"), 1)
    A.eq(#w.errors, 0)
  end)
end

local function test_state_template_runs_onstate_snippet() -- TS15
  H.withTaint("retail", function()
    local f = _G.CreateFrame("Frame", "TKHState", _G.UIParent, "SecureHandlerStateTemplate")
    f:SetAttribute("_onstate-combat", "self:SetAttribute('seen', stateid .. '=' .. newstate)")
    f:SetAttribute("state-combat", "yes")
    A.eq(f:GetAttribute("seen"), "combat=yes")
  end)
end

local function test_click_template_runs__onclick_snippet() -- TS15
  H.withTaint("retail", function(w, _, s)
    local h = handler("TKHClick")
    h:SetAttribute("_onclick", "self:SetAttribute('got', button .. tostring(down))")
    s:click(h)
    A.eq(h:GetAttribute("got"), "LeftButtonfalse")
    A.eq(#w.errors, 0)
  end)
end

local function test_other_event_templates_run_their_snippets() -- TS15
  H.withTaint("retail", function(w, _, s)
    local f = _G.CreateFrame("Frame", "TKHSimple", _G.UIParent, "SecureHandlerShowHideTemplate")
    f:SetAttribute("_onshow", "self:SetAttribute('shown', 'yes')")
    f:SetAttribute("_onhide", "self:SetAttribute('shown', 'no')")
    f:Hide()
    A.eq(f:GetAttribute("shown"), "no")
    f:Show()
    A.eq(f:GetAttribute("shown"), "yes")
    local e = _G.CreateFrame("Frame", "TKHEnter", _G.UIParent, "SecureHandlerEnterLeaveTemplate")
    e:SetSize(20, 20)
    e:SetPoint("CENTER")
    e:EnableMouse(true)
    e:SetAttribute("_onenter", "self:SetAttribute('hover', 'in')")
    e:SetAttribute("_onleave", "self:SetAttribute('hover', 'out')")
    s:enter(e)
    A.eq(e:GetAttribute("hover"), "in")
    s:leave(e)
    A.eq(e:GetAttribute("hover"), "out")
    local d = _G.CreateFrame("Button", "TKHDouble", _G.UIParent, "SecureHandlerDoubleClickTemplate")
    d:SetAttribute("_ondoubleclick", "self:SetAttribute('dbl', button)")
    w:callScript(d, "OnDoubleClick", "RightButton")
    A.eq(d:GetAttribute("dbl"), "RightButton")
    local m = _G.CreateFrame("Frame", "TKHWheel", _G.UIParent, "SecureHandlerMouseWheelTemplate")
    m:SetAttribute("_onmousewheel", "self:SetAttribute('delta', delta)")
    w:callScript(m, "OnMouseWheel", -1)
    A.eq(m:GetAttribute("delta"), -1)
  end)
end

local function test_every_handler_template_is_protected_and_has_the_api() -- TS15
  H.withTaint("retail", function(w)
    for _, kind in ipairs({ "Base", "State", "Attribute", "Click", "DoubleClick", "Drag", "MouseUpDown", "MouseWheel", "EnterLeave", "ShowHide" }) do
      local f = _G.CreateFrame("Button", nil, _G.UIParent, "SecureHandler" .. kind .. "Template")
      A.eq(f:IsProtected(), true, kind)
      A.same(
        { type(f.Execute), type(f.SetFrameRef), type(f.WrapScript), type(f.UnwrapScript) },
        { "function", "function", "function", "function" },
        kind
      )
    end
    A.eq(w.unscripted["template:SecureHandlerDoubleClickTemplate"], nil)
  end)
end

local function test_snippet_error_goes_to_the_error_handler_and_continues() -- TS15
  H.withTaint("retail", function(w, _, s)
    local h = handler("TKHErr")
    local target = hiddenTarget("TKHErrT")
    h:SetFrameRef("p", target)
    h:SetAttribute("_onclick", "self:Boom()")
    s:click(h)
    A.eq(#w.errors, 1)
    A.contains(lastError(w), "Call failed")
    h:SetAttribute("_onclick", "self:GetFrameRef('p'):Show()")
    s:click(h)
    A.eq(target:IsShown(), true)
    A.eq(#w.errors, 1)
  end)
end

local function test_set_frame_ref_roundtrip() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHRef", "SecureHandlerBaseTemplate")
    local target = hiddenTarget("TKHRefT")
    h:SetFrameRef("p", target)
    A.eq(SecureEnv.run(w, h, "return self:GetFrameRef('p'):GetName(), self:GetFrameRef('none')")[2], "TKHRefT")
    A.eq(h:GetAttribute("frameref-p") ~= nil, true)
    A.eq(SecureEnv.run(w, h, "return self:GetFrameRef('none')")[2], nil)
    A.errors(function()
      h:SetFrameRef(1, target)
    end, "Invalid body")
    A.errors(function()
      h:SetFrameRef("q", {})
    end, "Invalid reference frame")
  end)
end

local function test_handle_methods_refuse_unprotected_frames_in_combat() -- TS15
  H.withTaint("retail", function(w, _, s)
    local h = handler("TKHComb")
    local plain = _G.CreateFrame("Frame", "TKHCombPlain", _G.UIParent)
    plain:Hide()
    h:SetFrameRef("plain", plain)
    h:SetAttribute("_onclick", "self:GetFrameRef('plain'):Show()")
    s:click(h)
    A.eq(plain:IsShown(), true) -- out of combat any frame
    plain:Hide()
    H.setCombat(w, true)
    s:click(h)
    A.eq(plain:IsShown(), false)
    A.contains(lastError(w), "Invalid frame handle")
  end)
end

local function test_handle_hide_sets_statehidden() -- TS15
  H.withTaint("retail", function(w)
    local h = handler("TKHHide", "SecureHandlerBaseTemplate")
    local target = _G.CreateFrame("Frame", "TKHHideT", _G.UIParent, "SecureFrameTemplate")
    h:SetFrameRef("p", target)
    SecureEnv.run(w, h, "self:GetFrameRef('p'):Hide()")
    A.same({ target:IsShown(), target:GetAttribute("statehidden") }, { false, true })
    SecureEnv.run(w, h, "self:GetFrameRef('p'):Show()")
    A.same({ target:IsShown(), target:GetAttribute("statehidden") }, { true, nil })
  end)
end

local function wrapSetup(name)
  local hdr = _G.CreateFrame("Frame", name .. "Hdr", _G.UIParent, "SecureHandlerBaseTemplate")
  local b = _G.CreateFrame("Button", name, _G.UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp")
  b:SetAttribute("type", "spell")
  b:SetAttribute("spell", "Kit Strike")
  return hdr, b
end

local function recordCasts(w)
  local cast = {}
  w:stub("CastSpellByName", function(...)
    cast[#cast + 1] = { ... }
  end)
  return cast
end

local function test_wrap_script_pre_body_runs_before_the_click_action() -- TS15
  H.withTaint("retail", function(w, _, s)
    local hdr, b = wrapSetup("TKWrap")
    local cast = recordCasts(w)
    _G.SecureHandlerWrapScript(b, "OnClick", hdr, "self:SetAttribute('spell', 'Kit Bolt')")
    s:click(b)
    A.eq(cast[1][1], "Kit Bolt")
    b:SetScript("OnClick", function() end) -- a later SetScript replaces the wrap: the next click runs only the new script
    s:click(b)
    A.eq(#cast, 1)
    A.eq(#w.errors, 0)
  end)
end

local function test_pre_body_false_skips_the_handler_and_post_runs_only_with_a_message() -- TS15
  H.withTaint("retail", function(w, _, s)
    local hdr, b = wrapSetup("TKWrap2")
    local cast = recordCasts(w)
    hdr:WrapScript(b, "OnClick", "return button == 'LeftButton' and false", "self:SetAttribute('post', message)")
    s:click(b)
    A.same({ #cast, b:GetAttribute("post") }, { 0, nil }) -- false skips the handler and the post body
    hdr:UnwrapScript(b, "OnClick")
    hdr:WrapScript(b, "OnClick", "return nil, 'hello'", "self:SetAttribute('post', message .. button)")
    s:click(b)
    A.same({ #cast, b:GetAttribute("post") }, { 1, "helloLeftButton" })
    b:SetAttribute("post", nil)
    hdr:UnwrapScript(b, "OnClick")
    hdr:WrapScript(b, "OnClick", "x = 1", "self:SetAttribute('post', 'ran')")
    s:click(b)
    A.same({ #cast, b:GetAttribute("post") }, { 2, nil }) -- no message, no post body
    hdr:UnwrapScript(b, "OnClick")
    hdr:WrapScript(b, "OnClick", "return 'RightButton'")
    b:SetAttribute("type2", "spell")
    b:SetAttribute("spell2", "Kit Right")
    s:click(b)
    A.eq(cast[3][1], "Kit Right") -- a string first return replaces the button
  end)
end

local function test_pre_body_runs_in_combat_only_for_a_protected_frame() -- TS15
  H.withTaint("retail", function(w, _, s)
    local hdr, prot = wrapSetup("TKWrap3")
    local plain = _G.CreateFrame("Button", "TKWrap3Plain", _G.UIParent)
    plain:RegisterForClicks("AnyUp")
    local ran = 0
    plain:SetScript("OnClick", function()
      ran = ran + 1
    end)
    hdr:WrapScript(plain, "OnClick", "self:SetAttribute('pre', 'x')")
    hdr:WrapScript(prot, "OnClick", "self:SetAttribute('pre', 'x')")
    recordCasts(w)
    H.setCombat(w, true)
    s:click(plain)
    s:click(prot)
    A.same({ ran, plain:GetAttribute("pre"), prot:GetAttribute("pre") }, { 1, nil, "x" })
  end)
end

local function test_unwrap_script_restores_the_handler_and_returns_the_wrap() -- TS15
  H.withTaint("retail", function(_, _, s)
    local hdr = _G.CreateFrame("Frame", "TKWrap4Hdr", _G.UIParent, "SecureHandlerBaseTemplate")
    local b = _G.CreateFrame("Button", "TKWrap4", _G.UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    local ran = 0
    local function original()
      ran = ran + 1
    end
    b:SetScript("OnClick", original)
    hdr:WrapScript(b, "OnClick", "x = 1", "y = 2")
    A.eq(b:GetScript("OnClick") ~= original, true)
    local header, pre, post = hdr:UnwrapScript(b, "OnClick")
    A.same({ header == hdr, pre, post }, { true, "x = 1", "y = 2" })
    A.eq(b:GetScript("OnClick"), original)
    s:click(b)
    A.eq(ran, 1)
  end)
end

local function test_wrap_script_checks_its_arguments() -- TS15
  H.withTaint("retail", function()
    local hdr, b = wrapSetup("TKWrap5")
    local plain = _G.CreateFrame("Frame", "TKWrap5Plain", _G.UIParent)
    A.errors(function()
      _G.SecureHandlerWrapScript(b, "OnClick", plain, "x = 1")
    end, "Header frame must be explicitly protected")
    A.errors(function()
      hdr:WrapScript(b, "OnClick", 1)
    end, "Invalid pre-handler body")
    A.errors(function()
      hdr:WrapScript(b, "OnClick", "x = 1", 2)
    end, "Invalid post-handler body")
    A.errors(function()
      hdr:WrapScript(b, "OnTextChanged", "x = 1")
    end, "Frame does not support script")
    A.errors(function()
      hdr:WrapScript(b, "OnEnter", "x = 1")
      hdr:WrapScript(b, "OnLoad", "x = 1")
    end, "Unsupported script type")
    A.errors(function()
      hdr:WrapScript({}, "OnClick", "x = 1")
    end, "Invalid frame")
  end)
end

local function test_show_and_enter_wraps_pass_their_arguments() -- TS15
  H.withTaint("retail", function(w, _, s)
    local hdr = _G.CreateFrame("Frame", "TKWrap6Hdr", _G.UIParent, "SecureHandlerBaseTemplate")
    local f = _G.CreateFrame("Frame", "TKWrap6", _G.UIParent)
    f:SetSize(20, 20)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    local order = {}
    f:SetScript("OnShow", function()
      order[#order + 1] = "show"
    end)
    f:SetScript("OnEnter", function()
      order[#order + 1] = "enter"
    end)
    hdr:WrapScript(f, "OnShow", "self:SetAttribute('pre', 'show'); return nil, 'msg'", "self:SetAttribute('post', message)")
    hdr:WrapScript(f, "OnEnter", "return false")
    f:Hide()
    f:Show()
    A.same({ order, f:GetAttribute("pre"), f:GetAttribute("post") }, { { "show" }, "show", "msg" })
    s:enter(f)
    A.same(order, { "show" }) -- false skipped the OnEnter handler
    A.eq(#w.errors, 0)
  end)
end

local function test_leave_wrap_post_body_receives_the_message() -- TS15
  H.withTaint("retail", function(w, _, s)
    local hdr = _G.CreateFrame("Frame", "TKWrapLHdr", _G.UIParent, "SecureHandlerBaseTemplate")
    local f = _G.CreateFrame("Frame", "TKWrapL", _G.UIParent)
    f:SetSize(20, 20)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetScript("OnEnter", function() end)
    f:SetScript("OnLeave", function() end)
    hdr:WrapScript(f, "OnEnter", "return nil, 'hi'", "self:SetAttribute('postEnter', message)")
    hdr:WrapScript(f, "OnLeave", "return nil, 'bye'", "self:SetAttribute('postLeave', message)")
    s:enter(f)
    s:leave(f)
    A.same({ f:GetAttribute("postEnter"), f:GetAttribute("postLeave"), #w.errors }, { "hi", "bye", 0 })
  end)
end

return function()
  test_click_snippet_shows_a_protected_frame_in_combat()
  test_handler_api_is_refused_in_combat_for_every_caller()
  test_execute_runs_secure_for_tainted_callers_out_of_combat()
  test_execute_checks_its_header_and_body()
  test_a_tainted_click_cannot_run_a_snippet()
  test_a_tainted_click_in_combat_changes_no_protected_frame()
  test_a_tainted_state_attribute_runs_the_onstate_snippet_assumed()
  test_a_tainted_show_errors_in_the_onshow_snippet_as_the_client_does()
  test_a_tainted_state_attribute_in_combat_is_blocked_before_the_snippet()
  test_restricted_environment_hides_globals()
  test_a_snippet_calling_an_addon_replaced_global_runs_it_tainted_assumed()
  test_a_snippet_calling_an_addon_replaced_namespace_function_runs_it_tainted_assumed()
  test_a_handle_calls_the_class_method_not_an_addon_field()
  test_a_handle_ignores_an_addon_edit_of_the_class_method_table()
  test_snippet_globals_ignore_an_addon_replacement_made_before_the_first_snippet()
  test_snippets_see_a_string_name_the_kit_only_stubs()
  test_snippets_refuse_function_and_table_syntax()
  test_environment_variables_persist_per_header()
  test_attribute_template_runs__onattributechanged_snippet()
  test_state_template_runs_onstate_snippet()
  test_click_template_runs__onclick_snippet()
  test_other_event_templates_run_their_snippets()
  test_every_handler_template_is_protected_and_has_the_api()
  test_snippet_error_goes_to_the_error_handler_and_continues()
  test_set_frame_ref_roundtrip()
  test_handle_methods_refuse_unprotected_frames_in_combat()
  test_handle_hide_sets_statehidden()
  test_wrap_script_pre_body_runs_before_the_click_action()
  test_pre_body_false_skips_the_handler_and_post_runs_only_with_a_message()
  test_pre_body_runs_in_combat_only_for_a_protected_frame()
  test_unwrap_script_restores_the_handler_and_returns_the_wrap()
  test_wrap_script_checks_its_arguments()
  test_show_and_enter_wraps_pass_their_arguments()
  test_leave_wrap_post_body_receives_the_message()
end

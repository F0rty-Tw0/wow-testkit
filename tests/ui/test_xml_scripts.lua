-- XML <Scripts>: inline bodies, function= and method=, inherit=, and the OnLoad / OnShow a frame gets once it is built.
local A = require("assert")
local H = require("tests.helpers.xml")
local XmlBuild = require("ui.xml_build")
local XmlParse = require("ui.xml_parse")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local function logTo(w)
  local log = {}
  w:setGlobal("Mark", function(x)
    log[#log + 1] = x
  end)
  return log
end

local function test_inline_body_gets_self_and_the_handler_argument_names_assumed()
  local xml = '<Ui><Frame name="Ev"><Scripts><OnEvent>self.hit = { self, event, ... }</OnEvent></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Ev, "OnEvent", "PING", 1, 2)
    A.same({ _G.Ev.hit[1] == _G.Ev, _G.Ev.hit[2], _G.Ev.hit[3], _G.Ev.hit[4] }, { true, "PING", 1, 2 })
  end)
end

local function test_on_click_body_gets_button_and_down()
  local xml = '<Ui><Button name="Bt"><Scripts><OnClick>self.args = { button, down }</OnClick></Scripts></Button></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Bt, "OnClick", "LeftButton", true)
    A.same(_G.Bt.args, { "LeftButton", true })
  end)
end

local function test_on_value_changed_body_gets_value()
  local xml = '<Ui><Slider name="Sl"><Scripts><OnValueChanged>self.got = value</OnValueChanged></Scripts></Slider></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Sl, "OnValueChanged", 7)
    A.eq(_G.Sl.got, 7)
  end)
end

local function test_function_attribute_names_a_function()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Fn"><Scripts><OnShow function="MyShow"/></Scripts></Frame></Ui>' }, function(w, ctx)
    local seen
    w:setGlobal("MyShow", function(self)
      seen = self
    end)
    H.load(w, ctx, "Ui.xml")
    A.eq(seen, _G.Fn) -- shown at creation, so OnShow ran after OnLoad
  end)
end

local function test_function_attribute_is_looked_up_at_build_time_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Fn"><Scripts><OnShow function="MyShow"/></Scripts></Frame></Ui>' }, function(w, ctx)
    w:setGlobal("MyShow", function() end)
    H.load(w, ctx, "Ui.xml")
    w:setGlobal("MyShow", nil)
    A.truthy(_G.Fn:GetScript("OnShow"), "the function captured at build time stays")
  end)
end

local function test_method_attribute_calls_the_mixin_method_on_load()
  local xml = '<Ui><Frame name="Mt" mixin="SetupMixin"><Scripts><OnLoad method="Setup"/></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    w:setGlobal("SetupMixin", {
      Setup = function(self)
        self.ready = true
      end,
    })
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Mt.ready, true)
  end)
end

local function test_method_attribute_passes_the_handler_arguments_assumed()
  local xml = '<Ui><Frame name="Mt" mixin="SetupMixin"><Scripts><OnEvent method="Take"/></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    w:setGlobal("SetupMixin", {
      Take = function(self, event, arg)
        self.got = { event, arg }
      end,
    })
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Mt, "OnEvent", "PING", 5)
    A.same(_G.Mt.got, { "PING", 5 })
  end)
end

local function test_method_that_the_frame_lacks_names_the_method_and_the_xml_line()
  local xml = '<Ui>\n<Frame name="Mm"><Scripts>\n<OnLoad method="Nope"/></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].message, "addon:XmlT/Ui.xml:3: <OnLoad> method 'Nope' not found on Mm")
  end)
end

local function test_handler_tags_match_ignoring_case_assumed() -- (X16)
  local xml = '<Ui><Frame name="Lc"><Scripts><onload>Mark("loaded")</onload><onevent>self.got = event</onevent></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Lc, "OnEvent", "PING")
    A.same(log, { "loaded" })
    A.eq(_G.Lc.got, "PING")
    A.eq(reportText(ctx), "")
  end)
end

local function test_on_load_runs_after_children_exist()
  local xml = [[
<Ui><Frame name="Pr"><Scripts><OnLoad>Mark(self.Kid and "has kid" or "no kid")</OnLoad></Scripts>
  <Frames><Frame parentKey="Kid"/></Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "has kid" })
  end)
end

local function test_on_load_runs_after_layers_and_key_values()
  local xml = [[
<Ui><Frame name="Pr"><Scripts><OnLoad>Mark(self.Label and self.tag)</OnLoad></Scripts>
  <KeyValues><KeyValue key="tag" value="T"/></KeyValues>
  <Layers><Layer level="ARTWORK"><FontString parentKey="Label"/></Layer></Layers></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "T" })
  end)
end

local function test_a_child_on_load_runs_before_its_parents_assumed()
  local xml = [[
<Ui><Frame name="Pr"><Scripts><OnLoad>Mark("P")</OnLoad></Scripts>
  <Frames><Frame parentKey="Kid"><Scripts><OnLoad>Mark("K")</OnLoad></Scripts></Frame></Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "K", "P" })
  end)
end

local function test_on_show_follows_on_load_for_a_shown_frame()
  local xml = '<Ui><Frame name="Sh"><Scripts><OnLoad>Mark("load")</OnLoad><OnShow>Mark("show")</OnShow></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "load", "show" })
  end)
end

local function test_hidden_frame_gets_on_load_but_no_on_show()
  local xml = '<Ui><Frame name="Hd" hidden="true"><Scripts><OnLoad>Mark("load")</OnLoad><OnShow>Mark("show")</OnShow></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "load" })
  end)
end

local function test_hidden_frame_fires_no_on_hide_assumed()
  local xml = '<Ui><Frame name="Hd" hidden="true"><Scripts><OnHide>Mark("hide")</OnHide></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, {})
  end)
end

local function test_hidden_parent_suppresses_a_child_on_show_assumed()
  local xml = [[
<Ui><Frame name="Pr" hidden="true"><Frames><Frame parentKey="Kid"><Scripts><OnShow>Mark("kid show")</OnShow></Scripts></Frame></Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, {})
  end)
end

local function test_error_in_a_body_names_the_xml_line()
  local xml = '<Ui>\n<Frame name="Er">\n<Scripts>\n<OnLoad>local x = 1\nerror("bad")</OnLoad>\n</Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml:5:")
  end)
end

local function test_unsupported_handler_is_reported_and_skipped()
  local xml = '<Ui>\n<Frame name="Un"><Scripts><OnClick>Mark("x")</OnClick></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:2: Frame has no script handler 'OnClick'; ignored")
    A.eq(_G.Un:GetScript("OnClick"), nil)
  end)
end

local function test_intrinsic_order_is_accepted_without_a_report()
  local xml = '<Ui><Frame name="Io"><Scripts><OnLoad intrinsicOrder="postcreate">Mark("x")</OnLoad></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.eq(reportText(ctx), "")
  end)
end

local function test_missing_function_global_is_reported_and_skipped_assumed()
  local xml = '<Ui>\n<Frame name="Mf"><Scripts><OnShow function="Nope"/></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:2:")
    A.contains(reportText(ctx), "Nope")
    A.eq(_G.Mf:GetScript("OnShow"), nil)
  end)
end

local function test_body_that_does_not_compile_is_reported_and_loading_continues()
  local xml = '<Ui><Frame name="Bd"><Scripts>\n<OnShow>this is not lua</OnShow><OnLoad>Mark("loaded")</OnLoad></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml:2:")
    A.eq(_G.Bd:GetScript("OnShow"), nil)
    A.same(log, { "loaded" })
  end)
end

local function test_on_enter_through_xml_enables_the_mouse()
  local xml = '<Ui><Frame name="Mo"><Scripts><OnEnter>Mark("in")</OnEnter></Scripts></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Mo:IsMouseEnabled(), true)
  end)
end

-- Runs a <Scripts> element on a Button whose OnClick was set to log "old"; returns the log after one click.
local function clickAfter(inheritAttr)
  local result
  H.withXml({}, function(w, ctx)
    local log = logTo(w)
    local button = _G.CreateFrame("Button", "Cmb")
    button:SetScript("OnClick", function()
      log[#log + 1] = "old"
    end)
    local scripts = XmlParse.parse("<Scripts><OnClick " .. inheritAttr .. '>Mark("new")</OnClick></Scripts>')
    XmlBuild.handlers.scripts(w, button, w.ui.state[button], scripts, XmlBuild.session(ctx))
    w:callScript(button, "OnClick")
    result = log
  end)
  return result
end

local function test_inherit_prepend_runs_the_new_handler_first_assumed()
  A.same(clickAfter('inherit="prepend"'), { "new", "old" })
end

local function test_inherit_append_runs_the_new_handler_last_assumed()
  A.same(clickAfter('inherit="append"'), { "old", "new" })
end

local function test_inherit_none_replaces_the_existing_handler_assumed()
  A.same(clickAfter('inherit="none"'), { "new" })
  A.same(clickAfter(""), { "new" })
end

local function test_a_body_that_closes_its_handler_early_is_reported_and_the_load_goes_on()
  local xml = [[<Ui>
<Frame name="BrkA"><Scripts><OnShow>end, (function() BrkRan = true; error("boom") end)(), function(self)</OnShow></Scripts></Frame>
<Frame name="BrkB"/>
<Script>local _, ns = ...; ns.after = true</Script></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    A.eq(H.load(w, ctx, "Ui.xml"), true)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml:2:")
    A.eq(rawget(_G, "BrkRan"), nil)
    A.eq(w:getScript(_G.BrkA, "OnShow"), nil)
    A.eq(_G.BrkB ~= nil, true)
    A.eq(ctx.ns.after, true)
  end)
end

return function()
  test_a_body_that_closes_its_handler_early_is_reported_and_the_load_goes_on()
  test_inline_body_gets_self_and_the_handler_argument_names_assumed()
  test_on_click_body_gets_button_and_down()
  test_on_value_changed_body_gets_value()
  test_function_attribute_names_a_function()
  test_function_attribute_is_looked_up_at_build_time_assumed()
  test_method_attribute_calls_the_mixin_method_on_load()
  test_method_attribute_passes_the_handler_arguments_assumed()
  test_method_that_the_frame_lacks_names_the_method_and_the_xml_line()
  test_handler_tags_match_ignoring_case_assumed()
  test_on_load_runs_after_children_exist()
  test_on_load_runs_after_layers_and_key_values()
  test_a_child_on_load_runs_before_its_parents_assumed()
  test_on_show_follows_on_load_for_a_shown_frame()
  test_hidden_frame_gets_on_load_but_no_on_show()
  test_hidden_frame_fires_no_on_hide_assumed()
  test_hidden_parent_suppresses_a_child_on_show_assumed()
  test_error_in_a_body_names_the_xml_line()
  test_unsupported_handler_is_reported_and_skipped()
  test_intrinsic_order_is_accepted_without_a_report()
  test_missing_function_global_is_reported_and_skipped_assumed()
  test_body_that_does_not_compile_is_reported_and_loading_continues()
  test_on_enter_through_xml_enables_the_mouse()
  test_inherit_prepend_runs_the_new_handler_first_assumed()
  test_inherit_append_runs_the_new_handler_last_assumed()
  test_inherit_none_replaces_the_existing_handler_assumed()
end

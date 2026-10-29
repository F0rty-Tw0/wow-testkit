-- XML intrinsic frame types (row X24): an element with intrinsic="true" declares a frame type that CreateFrame and XML
-- tags then build, with the element's content applied first and its scripts bound as intrinsic handlers.
local A = require("assert")
local H = require("tests.helpers.xml")

local PAD = [[
<Ui>
  <Script>KitPadMixin = { Tap = function(self) return "tap" end }</Script>
  <Button name="KitPad" mixin="KitPadMixin" intrinsic="true">
    <KeyValues><KeyValue key="kind" value="pad"/></KeyValues>
    <Size x="37" y="37"/>
    <Layers><Layer level="BORDER"><Texture name="$parentIcon" parentKey="icon"/></Layer></Layers>
    <Scripts>
      <OnLoad>Mark("intrinsic load")</OnLoad>
      <OnShow intrinsicOrder="postcall">Mark("intrinsic show")</OnShow>
    </Scripts>
  </Button>
  <Frame name="SmallT" virtual="true"><Size x="10" y="10"/></Frame>
</Ui>]]

local function logTo(w)
  local log = {}
  w:setGlobal("Mark", function(x)
    log[#log + 1] = x
  end)
  return log
end

local function test_create_frame_builds_an_xml_intrinsic_that_reports_its_base_type()
  H.withXml({ ["Ui.xml"] = PAD }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.KitPad, nil) -- the declaration builds no frame
    local pad = _G.CreateFrame("KitPad", "P1", _G.UIParent)
    A.same({ pad:GetObjectType(), pad:IsObjectType("KitPad"), pad:GetSize() }, { "Button", true, 37, 37 }) -- D8
    A.same({ pad.icon == _G.P1Icon, pad.kind, pad:Tap() }, { true, "pad", "tap" })
    A.same(log, { "intrinsic load" }) -- the intrinsic's OnLoad fires with no template list
    A.eq(table.concat(ctx.report, "\n"), "")
  end)
end

local function test_xml_tag_applies_the_intrinsic_before_inherits_and_its_own_content()
  local xml = PAD:gsub(
    "</Ui>",
    '<KitPad name="P2" inherits="SmallT"/><KitPad name="P3"><Scripts><OnLoad>Mark("own load")</OnLoad>'
      .. '<OnShow>Mark("own show")</OnShow></Scripts></KitPad></Ui>'
  )
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.P2:GetSize() }, { 10, 10 })
    -- P2: intrinsic OnLoad, then OnShow (row X6) with the postcall handler; P3: precall, own, own, postcall
    A.same(log, { "intrinsic load", "intrinsic show", "intrinsic load", "own load", "own show", "intrinsic show" })
    _G.P3:SetScript("OnShow", nil) -- an intrinsic script cannot be removed
    _G.P3:Hide()
    _G.P3:Show()
    A.eq(log[#log], "intrinsic show")
  end)
end

local function test_an_intrinsic_belongs_to_the_world_that_loaded_it()
  H.withXml({ ["Ui.xml"] = PAD }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
  end)
  H.withXml({}, function()
    A.contains(select(2, pcall(_G.CreateFrame, "KitPad")), "unknown frame type 'KitPad'")
  end)
end

-- A real intrinsic replaces the kit fake of the same name (framexml/fakes/scrolling_message_frame.lua).
local function test_an_xml_intrinsic_replaces_the_kit_fake_of_its_name()
  local xml = '<Ui><Script>SmfMixin = { Real = true }</Script><Frame name="ScrollingMessageFrame" mixin="SmfMixin" intrinsic="true"/></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    A.eq(type(_G.CreateFrame("ScrollingMessageFrame").AddMessage), "function")
    H.load(w, ctx, "Ui.xml")
    local log = _G.CreateFrame("ScrollingMessageFrame")
    A.same({ log.Real, log.AddMessage, log:GetObjectType() }, { true, nil, "Frame" })
  end)
end

return function()
  test_create_frame_builds_an_xml_intrinsic_that_reports_its_base_type()
  test_xml_tag_applies_the_intrinsic_before_inherits_and_its_own_content()
  test_an_intrinsic_belongs_to_the_world_that_loaded_it()
  test_an_xml_intrinsic_replaces_the_kit_fake_of_its_name()
end

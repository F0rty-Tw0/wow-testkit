-- Animation targets: SetTarget (object or name), SetChildKey, SetTargetKey, SetTargetName and SetTargetParent, and the
-- XML attributes that set them. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local AG = require("tests.helpers.anim_group")
local AnimEffects = require("ui.anim_effects")
local H = require("tests.helpers.xml")
local HW = require("tests.helpers.widgets")

local group = AG.group
local withWidgets = HW.withWidgets

-- source: confirmed (W73) Blizzard XML: childKey="SpellHighlightTexture" on an animation names a key of the group's owner.
local function test_child_key_targets_a_field_of_the_group_owner()
  withWidgets("retail", function()
    local frame, _, alpha = group()
    local glow = frame:CreateTexture()
    frame.Glow = glow
    A.eq(alpha:SetChildKey("Glow"), true)
    A.eq(alpha:GetTarget(), glow)
  end)
end

local function test_child_key_resolves_when_the_field_is_set_later()
  withWidgets("retail", function()
    local frame, _, alpha = group()
    alpha:SetChildKey("Late")
    A.eq(alpha:GetTarget(), nil)
    frame.Late = frame:CreateTexture()
    A.eq(alpha:GetTarget(), frame.Late)
  end)
end

-- source: confirmed (W73) Blizzard XML: targetKey="$parent.$parent.MedalGlow" on an animation reads $parent as the group,
-- then the group's owner, and MedalGlow as a field of that owner.
local function test_target_key_walks_parents_from_the_animation()
  withWidgets("retail", function()
    local frame, _, alpha = group()
    frame.MedalGlow = frame:CreateTexture()
    alpha:SetTargetKey("$parent.$parent.MedalGlow")
    A.eq(alpha:GetTarget(), frame.MedalGlow)
    alpha:SetTargetKey("$parent.$parent")
    A.eq(alpha:GetTarget(), frame)
    alpha:SetTargetKey("$parent.$parent.Nothing")
    A.eq(alpha:GetTarget(), nil)
  end)
end

-- source: confirmed (W73) Blizzard XML: target="$parentGlow" is the global named after the owner plus "Glow"; target="$parent"
-- alone is the owner.
local function test_target_name_substitutes_the_owner_name_into_a_global()
  withWidgets("retail", function()
    local frame = _G.CreateFrame("Frame", "T611Owner")
    local alpha = frame:CreateAnimationGroup():CreateAnimation("Alpha")
    local glow = _G.CreateFrame("Frame", "T611OwnerGlow")
    alpha:SetTargetName("$parentGlow")
    A.eq(alpha:GetTarget(), glow)
    alpha:SetTargetName("$parent")
    A.eq(alpha:GetTarget(), frame)
    alpha:SetTarget("$parentGlow")
    A.eq(alpha:GetTarget(), glow)
    alpha:SetTargetName("NoSuchGlobal")
    A.eq(alpha:GetTarget(), nil)
  end)
end

-- source: assumed (W73) SetTargetParent takes no argument and targets the group's owner, the object "$parent" names.
local function test_target_parent_targets_the_owner_assumed()
  withWidgets("retail", function()
    local frame, _, alpha = group()
    alpha:SetTarget(_G.CreateFrame("Frame"))
    A.eq(alpha:SetTargetParent(), true)
    A.eq(alpha:GetTarget(), frame)
  end)
end

local function test_the_last_target_setter_wins()
  withWidgets("retail", function()
    local frame, _, alpha = group()
    local other = _G.CreateFrame("Frame")
    frame.Child = frame:CreateTexture()
    alpha:SetChildKey("Child")
    alpha:SetTarget(other)
    A.eq(alpha:GetTarget(), other)
    alpha:SetChildKey("Child")
    A.eq(alpha:GetTarget(), frame.Child)
  end)
end

local XML = [[
<Ui><Frame name="Host"><Layers><Layer><Texture parentKey="Icon"/></Layer></Layers>
  <Frame name="$parentGlow"/>
  <Animations><AnimationGroup parentKey="Anim">
    <Alpha parentKey="ByKey" childKey="Icon" duration="1"/>
    <Alpha parentKey="ByName" target="$parentGlow" duration="1"/>
    <Alpha parentKey="ByPath" targetKey="$parent.$parent.Icon" duration="1"/>
    <Alpha parentKey="Own" duration="1"/>
  </AnimationGroup></Animations></Frame></Ui>]]

local function test_xml_target_attributes_resolve_against_the_built_frame() -- W73
  H.withXml({ ["Ui.xml"] = XML }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local anim = _G.Host.Anim
    A.eq(anim.ByKey:GetTarget(), _G.Host.Icon)
    A.eq(anim.ByName:GetTarget(), _G.HostGlow)
    A.eq(anim.ByPath:GetTarget(), _G.Host.Icon)
    A.eq(anim.Own:GetTarget(), _G.Host)
  end)
end

local function test_an_xml_alpha_animates_its_target_not_the_owner() -- W61
  H.withXml({ ["Ui.xml"] = XML }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local anim = _G.Host.Anim
    anim:Play()
    w:advance(0.5)
    local function alphaOf(obj)
      return AnimEffects.effects(w, obj).alpha
    end
    -- Icon is the target of two of the four animations (they multiply), the glow of one and the owner of one
    A.same({ alphaOf(_G.Host.Icon), alphaOf(_G.HostGlow), alphaOf(_G.Host) }, { 0.25, 0.5, 0.5 })
  end)
end

return function()
  test_child_key_targets_a_field_of_the_group_owner()
  test_child_key_resolves_when_the_field_is_set_later()
  test_target_key_walks_parents_from_the_animation()
  test_target_name_substitutes_the_owner_name_into_a_global()
  test_target_parent_targets_the_owner_assumed()
  test_the_last_target_setter_wins()
  test_xml_target_attributes_resolve_against_the_built_frame()
  test_an_xml_alpha_animates_its_target_not_the_owner()
end

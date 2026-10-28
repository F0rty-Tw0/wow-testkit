-- Protected frames: a tainted call to a method the docs flag protected is refused on a protected frame in combat and
-- fires ADDON_ACTION_BLOCKED, explicit and implicit protection (IsProtected), CanChangeProtectedState, and forbidden
-- objects. Lua 5.1 only.
local A = require("assert")
local Combat = require("tests.helpers.combat")
local H = require("tests.helpers.taint")
local TaintFrames = require("taint_frames")

-- The ADDON_ACTION events the world fired so far, each as { event, addon, function }.
local function watch(w)
  local log = Combat.watch(w, { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" })
  return function()
    local out = {}
    for i, entry in ipairs(log) do
      out[i] = { entry.event, entry[3], entry[4] }
    end
    return out
  end
end

local function secureButton(name, parent)
  return _G.CreateFrame("Button", name, parent or _G.UIParent, "SecureActionButtonTemplate")
end

local function test_tainted_show_on_a_protected_frame_is_blocked_in_combat() -- TS9
  H.withTaint("retail", function(w)
    local b = secureButton("TKSec")
    b:Hide()
    local events = watch(w)
    H.run(w, "Foo", "TKSec:Show()")
    A.eq(b:IsShown(), true) -- out of combat: allowed
    b:Hide()
    H.setCombat(w, true)
    H.run(w, "Foo", "TKSec:Show()")
    A.eq(b:IsShown(), false)
    A.same(events(), { { "ADDON_ACTION_BLOCKED", "Foo", "TKSec:Show()" } }) -- TS10: the frame's global name
    w:run("blizzard", function()
      b:Show()
    end)
    A.eq(b:IsShown(), true) -- secure code may
  end)
end

local function test_unnamed_frame_is_reported_by_its_object_type_assumed() -- TS10
  H.withTaint("retail", function(w)
    local b = secureButton(nil)
    b:Hide()
    local events = watch(w)
    H.setCombat(w, true)
    H.run(w, "Foo", "local f = ...; f:Show()", b)
    A.eq(b:IsShown(), false)
    A.same(events(), { { "ADDON_ACTION_BLOCKED", "Foo", "Button:Show()" } })
  end)
end

local function test_unprotected_frame_is_never_blocked() -- TS9
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Frame", "TKPlain", _G.UIParent)
    f:Hide()
    local events = watch(w)
    H.setCombat(w, true)
    H.run(w, "Foo", "TKPlain:Show()")
    A.eq(f:IsShown(), true)
    A.same(events(), {})
  end)
end

local function test_set_attribute_is_restricted_on_protected_frames_in_combat() -- TS9
  H.withTaint("retail", function(w)
    local b = secureButton("TKSec2")
    H.setCombat(w, true)
    H.run(w, "Foo", "TKSec2:SetAttribute('type', 'spell')")
    A.eq(b:GetAttribute("type"), nil)
    A.same({ b:CanChangeProtectedState() }, { true }) -- asked from secure code
    H.setCombat(w, false)
    H.run(w, "Foo", "TKSec2:SetAttribute('type', 'spell')")
    A.eq(b:GetAttribute("type"), "spell") -- out of combat it runs
  end)
end

local function test_a_refused_call_changes_nothing() -- TS9
  H.withTaint("retail", function(w)
    local b = secureButton("TKSec3")
    b:SetPoint("CENTER")
    H.setCombat(w, true)
    H.run(w, "Foo", "TKSec3:ClearAllPoints(); TKSec3:SetPoint('TOPLEFT', 5, 5); TKSec3:SetSize(40, 40)")
    A.eq(b:GetNumPoints(), 1)
    A.eq(({ b:GetPoint() })[1], "CENTER")
  end)
end

local function test_is_protected_reports_explicit_and_implicit_assumed() -- TS12
  H.withTaint("retail", function()
    local plain = _G.CreateFrame("Frame")
    A.same({ plain:IsProtected() }, { false, false })
    local parent = _G.CreateFrame("Frame")
    local grandparent = _G.CreateFrame("Frame")
    parent:SetParent(grandparent)
    local child = secureButton(nil, parent)
    A.same({ child:IsProtected() }, { true, true })
    A.same({ parent:IsProtected() }, { true, false })
    A.same({ grandparent:IsProtected() }, { true, false }) -- recursively
    local anchorTarget = _G.CreateFrame("Frame", nil, plain)
    child:SetPoint("TOPLEFT", anchorTarget, "BOTTOMLEFT")
    A.same({ anchorTarget:IsProtected() }, { true, false }) -- a frame a protected frame is anchored to
    A.same({ plain:IsProtected() }, { true, false }) -- and the parent of that
    child:SetParent(nil)
    child:ClearAllPoints()
    A.same({ parent:IsProtected() }, { false, false }) -- cleared when no protected child or anchor is left
    A.same({ plain:IsProtected() }, { false, false })
  end)
end

local function test_implicitly_protected_frame_is_blocked_too_assumed() -- TS12
  H.withTaint("retail", function(w)
    local parent = _G.CreateFrame("Frame", "TKImplicit", _G.UIParent)
    secureButton(nil, parent)
    parent:Hide()
    local events = watch(w)
    H.setCombat(w, true)
    H.run(w, "Foo", "TKImplicit:Show()")
    A.eq(parent:IsShown(), false)
    A.same(events(), { { "ADDON_ACTION_BLOCKED", "Foo", "TKImplicit:Show()" } })
  end)
end

local function test_can_change_protected_state_is_false_for_tainted_callers_in_combat_assumed() -- TS12
  H.withTaint("retail", function(w)
    local b = secureButton("TKSec4")
    local plain = _G.CreateFrame("Frame", "TKPlain4", _G.UIParent)
    local function ask(src)
      return H.run(w, "Foo", src)[2]
    end
    A.eq(ask("return TKSec4:CanChangeProtectedState()"), true) -- out of combat
    H.setCombat(w, true)
    A.eq(ask("return TKSec4:CanChangeProtectedState()"), false)
    A.eq(ask("return TKPlain4:CanChangeProtectedState()"), true)
    A.eq(b:CanChangeProtectedState(), true) -- secure code
    A.eq(plain:CanChangeProtectedState(), true)
  end)
end

local function test_every_flagged_method_is_guarded() -- TS9
  for _, flavor in ipairs({ "retail" }) do
    H.withTaint(flavor, function(w)
      local b = secureButton("TKSecAll")
      local names = {}
      for _, doc in pairs(w.manifest.widgets) do
        for name, signature in pairs(doc.methods or {}) do
          if signature.protected and b[name] ~= nil then
            names[#names + 1] = name
          end
        end
      end
      table.sort(names)
      A.truthy(#names > 40, "the retail docs flag 62 methods, most of them on a Button")
      local events = watch(w)
      H.setCombat(w, true)
      local expected = {}
      for i, name in ipairs(names) do
        H.run(w, "Foo", "local f, m = ...; f[m](f)", b, name)
        expected[i] = { "ADDON_ACTION_BLOCKED", "Foo", "TKSecAll:" .. name .. "()" }
      end
      A.same(events(), expected)
    end)
  end
end

local function test_forbidden_object_raises_on_tainted_calls_assumed() -- TS13
  H.withTaint("retail", function(w)
    local f = _G.CreateFrame("Frame", "TKForbidden", _G.UIParent)
    TaintFrames.setForbidden(w, f, true)
    local events = watch(w)
    A.eq(f:IsForbidden(), true)
    A.eq(H.run(w, "Foo", "return TKForbidden:IsForbidden()")[2], true)
    A.eq(H.run(w, "Foo", "return TKForbidden:GetAttribute('x')")[1], true)
    A.eq(H.run(w, "Foo", "TKForbidden:SetAttribute('x', 1)")[1], true)
    A.eq(#w.errors, 0)
    A.eq(H.run(w, "Foo", "TKForbidden:GetName()")[1], false)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "forbidden object 'TKForbidden'")
    A.same(events(), {})
    f:GetName() -- secure code may
    TaintFrames.setForbidden(w, f, false)
    A.eq(f:IsForbidden(), false)
    A.eq(H.run(w, "Foo", "return TKForbidden:GetName()")[2], "TKForbidden")
  end)
end

local function test_classic_flavour_flags_apply() -- TS9
  H.withTaint("forever", function(w)
    local b = secureButton("TKSecForever")
    b:Hide()
    local events = watch(w)
    H.setCombat(w, true)
    H.run(w, "Foo", "TKSecForever:Show()")
    A.eq(b:IsShown(), false)
    A.same(events(), { { "ADDON_ACTION_BLOCKED", "Foo", "TKSecForever:Show()" } })
  end)
end

local function test_non_frame_regions_ignore_the_guard() -- TS9
  H.withTaint("retail", function(w)
    local b = secureButton("TKSec5")
    local texture = b:CreateTexture("TKTex5")
    b:SetPoint("TOPLEFT", texture, "BOTTOMLEFT") -- the texture is now implicitly protected, and still not guarded
    A.same({ texture:IsProtected() }, { true, false })
    texture:Hide()
    local events = watch(w)
    H.setCombat(w, true)
    H.run(w, "Foo", "TKTex5:Show(); TKTex5:SetPoint('CENTER', UIParent)") -- SetPoint is flagged in the docs for regions too
    A.eq(texture:IsShown(), true)
    A.eq(texture:GetNumPoints(), 1)
    A.same(events(), {})
  end)
end

return function()
  test_tainted_show_on_a_protected_frame_is_blocked_in_combat()
  test_unnamed_frame_is_reported_by_its_object_type_assumed()
  test_unprotected_frame_is_never_blocked()
  test_set_attribute_is_restricted_on_protected_frames_in_combat()
  test_a_refused_call_changes_nothing()
  test_is_protected_reports_explicit_and_implicit_assumed()
  test_implicitly_protected_frame_is_blocked_too_assumed()
  test_can_change_protected_state_is_false_for_tainted_callers_in_combat_assumed()
  test_every_flagged_method_is_guarded()
  test_forbidden_object_raises_on_tainted_calls_assumed()
  test_classic_flavour_flags_apply()
  test_non_frame_regions_ignore_the_guard()
end

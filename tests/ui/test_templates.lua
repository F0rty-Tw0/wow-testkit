-- XML templates on CreateFrame: parentKey children, size, mixin names, protection, unknown templates.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Templates = require("ui.templates")
local Widgets = require("ui.widgets")

local withWidgets = HW.withWidgets

local function test_ui_panel_button_has_every_parent_key_child()
  withWidgets("retail", function()
    local button = _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    A.eq(button.Left:GetObjectType(), "Texture")
    for _, child in ipairs(Templates.TEMPLATES.UIPanelButtonTemplate.children) do
      A.eq(button[child.key]:GetObjectType(), child.type, child.key)
    end
  end)
end

local function test_template_child_is_parented_to_the_frame()
  withWidgets("retail", function()
    local button = _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    A.eq(button.Left:GetParent(), button)
  end)
end

local function test_unknown_template_gives_plain_frame_and_counts_unscripted()
  withWidgets("retail", function(w)
    local frame = _G.CreateFrame("Frame", nil, nil, "NoSuchTemplate")
    A.eq(next(frame), nil)
    A.eq(w.unscripted["template:NoSuchTemplate"], 1)
  end)
end

local function test_secure_template_marks_frame_protected()
  withWidgets("retail", function(w)
    A.eq(Widgets.isProtected(w, _G.CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")), true)
    A.eq(Widgets.isProtected(w, _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")), false)
  end)
end

local function test_comma_separated_templates_apply_in_order()
  withWidgets("retail", function(w)
    local button = _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate, SecureActionButtonTemplate")
    A.eq(button.Left:GetObjectType(), "Texture")
    A.eq(Widgets.isProtected(w, button), true)
  end)
end

local function test_template_records_mixin_names()
  withWidgets("retail", function(w)
    local frame = _G.CreateFrame("Frame", nil, nil, "BackdropTemplate")
    A.same(w.ui.state[frame].mixins, { "BackdropTemplateMixin" })
  end)
end

local function test_existing_global_mixin_is_copied_onto_frame()
  withWidgets("retail", function(w)
    local function setBackdrop() end
    w:setGlobal("BackdropTemplateMixin", { SetBackdrop = setBackdrop })
    A.eq(_G.CreateFrame("Frame", nil, nil, "BackdropTemplate").SetBackdrop, setBackdrop)
  end)
end

local function test_template_size_is_applied()
  withWidgets("retail", function()
    local entry = Templates.TEMPLATES.UICheckButtonTemplate
    local check = _G.CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    A.same({ check:GetSize() }, entry.size)
  end)
end

return function()
  test_ui_panel_button_has_every_parent_key_child()
  test_template_child_is_parented_to_the_frame()
  test_unknown_template_gives_plain_frame_and_counts_unscripted()
  test_secure_template_marks_frame_protected()
  test_comma_separated_templates_apply_in_order()
  test_template_records_mixin_names()
  test_existing_global_mixin_is_copied_onto_frame()
  test_template_size_is_applied()
end

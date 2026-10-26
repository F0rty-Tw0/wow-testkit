-- Texture items of a render snapshot: exclusive source, only non-default look fields, the ignore-parent flags.
-- Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.render")
local S = require("tests.helpers.widget_snap")

local LOOK_FIELDS = { "texCoord", "vertexColor", "gradient", "blendMode", "desaturated", "rotation", "horizTile", "vertTile" }

-- A texture called name filling a host frame called name .. "Host".
local function texture(name)
  local host = S.anchored("Frame", name .. "Host")
  local tex = host:CreateTexture(name)
  tex:SetAllPoints()

  return tex
end

local function test_exclusive_source_is_exported_assumed() -- W1
  H.withRender(function(w)
    local tex = texture("TexA")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetColorTexture(0, 1, 0, 0.5)
    local item = S.snap(w, "TexA")
    A.same(item.color, { 0, 1, 0, 0.5 })
    A.eq(item.file, nil)
    A.eq(item.atlas, nil)
    tex:SetAtlas("Tooltip-Glow")
    item = S.snap(w, "TexA")
    A.eq(item.atlas, "atlas:tooltip-glow")
    A.eq(item.color, nil)
    A.eq(item.file, nil)
    tex:SetColorTexture(1, 0, 0)
    tex:SetTexture(136235)
    item = S.snap(w, "TexA")
    A.eq(item.file, "id:136235")
    A.eq(item.color, nil)
    A.eq(item.atlas, nil)
  end)
end

local function test_color_texture_alpha_defaults_to_one() -- W12
  H.withRender(function(w)
    texture("TexA"):SetColorTexture(0, 1, 0)
    A.same(S.snap(w, "TexA").color, { 0, 1, 0, 1 })
  end)
end

local function test_ignore_parent_alpha_stops_the_chain_assumed() -- W13
  H.withRender(function(w)
    local host = S.anchored("Frame", "AlphaHost")
    host:SetAlpha(0.5)
    local following = host:CreateTexture("TexA")
    following:SetAllPoints()
    following:SetColorTexture(1, 1, 1)
    local ignoring = host:CreateTexture("TexB")
    ignoring:SetAllPoints()
    ignoring:SetColorTexture(1, 1, 1)
    ignoring:SetIgnoreParentAlpha(true)
    ignoring:SetAlpha(0.8)
    A.eq(S.snap(w, "TexA").alpha, 0.5)
    A.eq(S.snap(w, "TexB").alpha, 0.8)
  end)
end

local function test_fresh_texture_exports_no_extra_fields()
  H.withRender(function(w)
    texture("TexA"):SetTexture("Interface\\Buttons\\WHITE8X8")
    local item = S.snap(w, "TexA")
    for _, field in ipairs(LOOK_FIELDS) do
      A.eq(item[field], nil)
    end
  end)
end

local function test_non_default_fields_are_exported()
  H.withRender(function(w)
    local tex = texture("TexA")
    tex:SetTexCoord(0.1, 0.9, 0.2, 0.8)
    tex:SetVertexColor(1, 0, 0, 0.5)
    tex:SetBlendMode("ADD")
    tex:SetDesaturated(true)
    tex:SetRotation(0.5)
    tex:SetHorizTile(true)
    local item = S.snap(w, "TexA")
    A.same(item.texCoord, { 0.1, 0.2, 0.1, 0.8, 0.9, 0.2, 0.9, 0.8 })
    A.same(item.vertexColor, { 1, 0, 0, 0.5 })
    A.eq(item.blendMode, "ADD")
    A.eq(item.desaturated, true)
    A.eq(item.rotation, 0.5)
    A.eq(item.horizTile, true)
    A.eq(item.vertTile, nil)
  end)
end

local function test_defaults_set_back_explicitly_are_not_exported()
  H.withRender(function(w)
    local tex = texture("TexA")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1)
    tex:SetBlendMode("BLEND")
    tex:SetDesaturated(false)
    tex:SetRotation(0)
    tex:SetVertTile(false)
    local item = S.snap(w, "TexA")
    for _, field in ipairs(LOOK_FIELDS) do
      A.eq(item[field], nil)
    end
  end)
end

local function test_gradient_exports_orientation_and_both_colours() -- W11
  H.withRender(function(w)
    local tex = texture("TexA")
    tex:SetGradient("HORIZONTAL", { r = 1, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 1, a = 1 })
    A.same(S.snap(w, "TexA").gradient, { orientation = "HORIZONTAL", min = { 1, 0, 0, 1 }, max = { 0, 0, 1, 1 } })
    tex:SetGradient("VERTICAL", { r = 0, g = 1, b = 0 }, { r = 1, g = 1, b = 1 })
    A.same(S.snap(w, "TexA").gradient, { orientation = "VERTICAL", min = { 0, 1, 0, 1 }, max = { 1, 1, 1, 1 } })
  end)
end

local function test_gradient_with_separate_numbers_exports_nothing() -- W11
  H.withRender(function(w)
    texture("TexA"):SetGradient("HORIZONTAL", 1, 0, 0, 0, 0, 1)
    A.eq(S.snap(w, "TexA").gradient, nil)
  end)
end

local function test_ignore_parent_scale_changes_the_rect_assumed() -- W13
  H.withRender(function(w)
    local parent = _G.CreateFrame("Frame", "ScaledParent", _G.UIParent)
    parent:SetScale(2)
    local child = _G.CreateFrame("Frame", "ScaledChild", parent)
    child:SetSize(50, 50)
    child:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
    A.eq(S.snap(w, "ScaledChild").rect.width, 100)
    child:SetIgnoreParentScale(true)
    A.eq(S.snap(w, "ScaledChild").rect.width, 50)
  end)
end

return function()
  test_exclusive_source_is_exported_assumed()
  test_color_texture_alpha_defaults_to_one()
  test_ignore_parent_alpha_stops_the_chain_assumed()
  test_fresh_texture_exports_no_extra_fields()
  test_non_default_fields_are_exported()
  test_defaults_set_back_explicitly_are_not_exported()
  test_gradient_exports_orientation_and_both_colours()
  test_gradient_with_separate_numbers_exports_nothing()
  test_ignore_parent_scale_changes_the_rect_assumed()
end

-- Texture behaviour (ui/behaviour_texture.lua): the source setters, texcoords, colours, flags, masks, the draw layer
-- sublevel and the ignore-parent flags. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local FrameXML = require("framexml.fakes")
local HC = require("tests.helpers.client")
local HW = require("tests.helpers.widgets")
local Tmp = require("tests.helpers.tmp")
local World = require("world")

local FULL_IMAGE = { 0, 0, 0, 1, 1, 0, 1, 1 }
local ATLAS = 'return { ["mini-atlas"] = { name = "Mini-Atlas", file = 111, width = 20, height = 10, left = 0, right = 0.5, top = 0, bottom = 1 } }'

local function newTexture()
  return _G.CreateFrame("Frame"):CreateTexture()
end

-- Runs fn(w) in a retail world with stage-1 FrameXML over a mini extract holding files; files nil is no extract.
local function withClient(files, fn)
  local extract = files and HC.extract(Tmp.dir("texture"), "retail", "1", files)
  local w = World.new({ flavor = "retail", client = extract })
  local ok, err = pcall(function()
    FrameXML.installStage1(w)
    fn(w)
  end)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_set_tex_coord_expands_four_numbers_to_eight() -- W4
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetTexCoord(0.1, 0.9, 0.2, 0.8)
    A.same({ t:GetTexCoord() }, { 0.1, 0.2, 0.1, 0.8, 0.9, 0.2, 0.9, 0.8 })
  end)
end

local function test_fresh_tex_coord_is_the_full_image_assumed() -- W4
  HW.withWidgets("retail", function()
    A.same({ newTexture():GetTexCoord() }, FULL_IMAGE)
  end)
end

local function test_eight_tex_coord_numbers_are_stored_as_given() -- W5
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetTexCoord(0.1, 0.9, 0.2, 0.8)
    t:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
    A.same({ t:GetTexCoord() }, FULL_IMAGE)
    t:SetTexCoord(0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)
    A.same({ t:GetTexCoord() }, { 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 })
  end)
end

local function test_get_texture_and_get_atlas_return_what_was_set() -- W2, W3
  HW.withWidgets("retail", function()
    local t = newTexture()
    A.eq(t:GetTexture(), nil)
    A.eq(t:GetAtlas(), nil)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    A.eq(t:GetTexture(), "Interface\\Buttons\\WHITE8X8")
    t:SetAtlas("common-icon-checkmark")
    A.eq(t:GetAtlas(), "common-icon-checkmark")
    t:SetTexture(136235)
    A.eq(t:GetTexture(), 136235)
    A.eq(t:GetAtlas(), nil)
  end)
end

local function test_set_texture_color_atlas_replace_each_other_assumed() -- W1, W2
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetColorTexture(1, 0, 0)
    A.eq(t:GetTexture(), nil)
    t:SetAtlas("common-icon-checkmark")
    A.eq(t:GetAtlas(), "common-icon-checkmark")
    t:SetTexture(136235)
    A.eq(t:GetAtlas(), nil)
    A.eq(t:GetTexture(), 136235)
    t:SetColorTexture(0, 0, 1)
    A.eq(t:GetTexture(), nil)
    A.eq(t:GetAtlas(), nil)
  end)
end

local function test_vertex_color_alpha_defaults_to_one() -- W6
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetVertexColor(0.5, 0.25, 0.125)
    A.same({ t:GetVertexColor() }, { 0.5, 0.25, 0.125, 1 })
    t:SetVertexColor(0.5, 0.25, 0.125, 0.5)
    A.same({ t:GetVertexColor() }, { 0.5, 0.25, 0.125, 0.5 })
  end)
end

local function test_fresh_vertex_color_is_white_assumed() -- W6
  HW.withWidgets("retail", function()
    A.same({ newTexture():GetVertexColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_defaults_and_setters_round_trip() -- W7, W8, W9, W10
  HW.withWidgets("retail", function(w)
    local t = newTexture()
    A.eq(t:GetBlendMode(), "BLEND")
    A.eq(t:IsDesaturated(), false)
    A.eq(t:GetRotation(), 0)
    A.eq(t:GetHorizTile(), false)
    A.eq(t:GetVertTile(), false)
    t:SetBlendMode("ADD")
    t:SetDesaturated(true)
    t:SetRotation(1.5)
    t:SetHorizTile(true)
    t:SetVertTile(true)
    A.eq(t:GetBlendMode(), "ADD")
    A.eq(t:IsDesaturated(), true)
    A.eq(t:GetRotation(), 1.5)
    A.eq(t:GetHorizTile(), true)
    A.eq(t:GetVertTile(), true)
    A.eq(w.unscripted["Texture:GetBlendMode"], nil)
  end)
end

local function test_mask_textures_are_counted_once_assumed() -- W15
  HW.withWidgets("retail", function()
    local t = newTexture()
    local mask = newTexture() -- CreateMaskTexture is still a no-op, so a texture stands in for the mask
    A.eq(t:GetNumMaskTextures(), 0)
    t:AddMaskTexture(mask)
    t:AddMaskTexture(mask)
    A.eq(t:GetNumMaskTextures(), 1)
    t:RemoveMaskTexture(mask)
    A.eq(t:GetNumMaskTextures(), 0)
  end)
end

local function test_draw_layer_sublevel_defaults_to_zero() -- W14
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetDrawLayer("OVERLAY")
    A.same({ t:GetDrawLayer() }, { "OVERLAY", 0 })
    t:SetDrawLayer("BORDER", 3)
    A.same({ t:GetDrawLayer() }, { "BORDER", 3 })
  end)
end

local function test_draw_layer_sublevel_clamps_assumed() -- W14
  HW.withWidgets("retail", function()
    local t = newTexture()
    t:SetDrawLayer("ARTWORK", 99)
    A.same({ t:GetDrawLayer() }, { "ARTWORK", 7 })
    t:SetDrawLayer("ARTWORK", -99)
    A.same({ t:GetDrawLayer() }, { "ARTWORK", -8 })
  end)
end

local function test_ignore_parent_flags_default_false_and_round_trip() -- W13
  HW.withWidgets("retail", function()
    for _, region in ipairs({ _G.CreateFrame("Frame"), newTexture() }) do
      A.eq(region:IsIgnoringParentAlpha(), false)
      A.eq(region:IsIgnoringParentScale(), false)
      region:SetIgnoreParentAlpha(true)
      region:SetIgnoreParentScale(true)
      A.eq(region:IsIgnoringParentAlpha(), true)
      A.eq(region:IsIgnoringParentScale(), true)
    end
  end)
end

local function test_set_atlas_use_atlas_size() -- W3
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = newTexture()
    t:SetAtlas("Mini-Atlas", true)
    A.eq(t:GetWidth(), 20)
    A.eq(t:GetHeight(), 10)
    A.eq(t:GetAtlas(), "Mini-Atlas")
  end)
end

local function test_set_atlas_without_use_atlas_size_keeps_the_size() -- W3
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = newTexture()
    t:SetSize(5, 6)
    t:SetAtlas("Mini-Atlas")
    A.eq(t:GetWidth(), 5)
    A.eq(t:GetHeight(), 6)
  end)
end

local function test_set_atlas_with_use_atlas_size_and_no_extract_keeps_the_size() -- W3
  withClient(nil, function()
    local t = newTexture()
    t:SetSize(5, 6)
    t:SetAtlas("Mini-Atlas", true)
    A.eq(t:GetWidth(), 5)
    A.eq(t:GetAtlas(), "Mini-Atlas")
  end)
end

local function test_set_atlas_with_an_unknown_atlas_keeps_the_size() -- W3
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = newTexture()
    t:SetSize(5, 6)
    t:SetAtlas("nope", true)
    A.eq(t:GetWidth(), 5)
  end)
end

-- The doc types both wrap modes cstring, but Blizzard code passes booleans (tbc Backdrop.lua:266 `SetTexture(file, tileVerts,
-- tileVerts)`, Blizzard_NameplateUnitFrame.lua:58 `SetTexture(path, true, true)` on retail and tbc); a table still fails.
local function test_set_texture_wrap_modes_take_a_boolean_from_addon_code()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    HW.withWidgets(flavor, function(w)
      local t = newTexture()
      w:run("addon", function()
        t:SetTexture(136235, true, false)
        t:SetTexture(136235, "REPEAT", "CLAMP")
      end)
      A.errors(function()
        w:run("addon", function()
          t:SetTexture(136235, {})
        end)
      end, "bad argument #2 'wrapModeHorizontal' (string expected, got table)")
    end)
  end
end

return function()
  test_set_texture_wrap_modes_take_a_boolean_from_addon_code()
  test_set_tex_coord_expands_four_numbers_to_eight()
  test_fresh_tex_coord_is_the_full_image_assumed()
  test_eight_tex_coord_numbers_are_stored_as_given()
  test_get_texture_and_get_atlas_return_what_was_set()
  test_set_texture_color_atlas_replace_each_other_assumed()
  test_vertex_color_alpha_defaults_to_one()
  test_fresh_vertex_color_is_white_assumed()
  test_defaults_and_setters_round_trip()
  test_mask_textures_are_counted_once_assumed()
  test_draw_layer_sublevel_defaults_to_zero()
  test_draw_layer_sublevel_clamps_assumed()
  test_ignore_parent_flags_default_false_and_round_trip()
  test_set_atlas_use_atlas_size()
  test_set_atlas_without_use_atlas_size_keeps_the_size()
  test_set_atlas_with_use_atlas_size_and_no_extract_keeps_the_size()
  test_set_atlas_with_an_unknown_atlas_keeps_the_size()
end

-- BackdropTemplateMixin: the minimal SetBackdrop family a BackdropTemplate frame gets (Task 6.7 owns the rest).
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local INFO = { bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 16 }

local function backdropFrame()
  return _G.CreateFrame("Frame", nil, _G.UIParent, "BackdropTemplate")
end

local function test_template_frames_get_set_backdrop()
  withFrameXML("retail", function()
    A.eq(type(backdropFrame().SetBackdrop), "function")
    A.eq(_G.CreateFrame("Frame").SetBackdrop, nil)
  end)
end

local function test_get_backdrop_returns_the_table_passed_and_nil_clears()
  withFrameXML("retail", function()
    local frame = backdropFrame()
    A.eq(frame:GetBackdrop(), nil)
    frame:SetBackdrop(INFO)
    A.eq(frame:GetBackdrop(), INFO)
    frame:SetBackdrop(nil)
    A.eq(frame:GetBackdrop(), nil)
  end)
end

local function test_colours_of_a_new_backdrop_read_white() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
    A.same({ frame:GetBackdropBorderColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_omitted_alpha_is_one() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0.1, 0.2, 0.3)
    frame:SetBackdropBorderColor(0.4, 0.5, 0.6)
    A.same({ frame:GetBackdropColor() }, { 0.1, 0.2, 0.3, 1 })
    A.same({ frame:GetBackdropBorderColor() }, { 0.4, 0.5, 0.6, 1 })
  end)
end

local function test_colours_without_a_backdrop_are_ignored_and_read_nothing() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdropColor(0, 0, 0, 0.5)
    A.eq(select("#", frame:GetBackdropColor()), 0)
    A.eq(select("#", frame:GetBackdropBorderColor()), 0)
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_set_backdrop_resets_the_colours() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_mixin_methods_do_not_count_as_unscripted()
  withFrameXML("retail", function(w)
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0)
    A.eq(w.unscripted["template:BackdropTemplate"], nil)
    A.eq(w.unscripted["Frame:SetBackdrop"], nil)
  end)
end

return function()
  test_template_frames_get_set_backdrop()
  test_get_backdrop_returns_the_table_passed_and_nil_clears()
  test_colours_of_a_new_backdrop_read_white()
  test_omitted_alpha_is_one()
  test_colours_without_a_backdrop_are_ignored_and_read_nothing()
  test_set_backdrop_resets_the_colours()
  test_mixin_methods_do_not_count_as_unscripted()
end

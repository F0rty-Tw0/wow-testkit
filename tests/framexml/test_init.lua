-- FrameXML.installStage1: installs the stage-1 fakes; destroy undoes all of them.
local A = require("assert")
local World = require("world")
local FrameXML = require("framexml.fakes")
local HF = require("tests.helpers.framexml")

local function test_stage1_installs_widgets_and_ui_parent()
  HF.withFrameXML("retail", function()
    A.eq(type(_G.CreateFrame), "function")
    A.eq(_G.UIParent:GetName(), "UIParent")
  end)
end

local function test_destroy_restores_globals_metatable_and_removes_fakes()
  local before = getmetatable(_G)
  local w = World.new({ flavor = "retail" })
  local ok, err = pcall(function()
    FrameXML.installStage1(w)
    A.truthy(_G.ChatFrame1)
  end)
  w:destroy()
  assert(ok, err)
  A.eq(getmetatable(_G), before)
  A.eq(_G.UIParent, nil)
  A.eq(rawget(_G, "ChatFrame1"), nil)
end

return function()
  test_stage1_installs_widgets_and_ui_parent()
  test_destroy_restores_globals_metatable_and_removes_fakes()
end

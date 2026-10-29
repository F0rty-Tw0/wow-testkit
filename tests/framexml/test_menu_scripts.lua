-- Menu API element scripts: which addon hooks a re-render or a Refresh drops. Every (re)initialize of a button,
-- checkbox or radio runs ButtonInitializer, which sets OnEnable, OnDisable and OnClick (Blizzard_Menu/
-- MenuTemplates.lua:184-186); only a render runs InitializeFrame, which also sets OnMouseDown, OnEnter and OnLeave on
-- every element (Menu.lua:1128-1130). A Refresh re-runs the initializers alone (ReinitializeAll, Menu.lua:1645-1665).
-- SetScript drops the hooks added before it (row F3).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")

local withFrameXML = HF.withFrameXML

local INITIALIZER_SCRIPTS = { "OnEnable", "OnDisable", "OnClick" }
local FRAME_SCRIPTS = { "OnMouseDown", "OnEnter", "OnLeave" }

local function noop() end

-- Hooks every script in names on frame; returns the set of script names whose hook ran since.
local function hookAll(frame, names)
  local ran = {}
  for _, name in ipairs(names) do
    frame:HookScript(name, function()
      ran[name] = true
    end)
  end
  return ran
end

local function fireAll(w, frame, names)
  for _, name in ipairs(names) do
    w:callScript(frame, name)
  end
end

local function both()
  local all = {}
  for _, list in ipairs({ INITIALIZER_SCRIPTS, FRAME_SCRIPTS }) do
    for _, name in ipairs(list) do
      all[#all + 1] = name
    end
  end
  return all
end

local function test_a_rerender_drops_hooks_on_every_script_it_sets()
  withFrameXML("retail", function(w)
    local dd = HM.newDropdownButton(function(_, root)
      root:CreateButton("Go", noop)
      root:CreateTitle("Title")
    end)
    dd:OpenMenu()
    local button, title = w.menus[1].entries[1].frame, w.menus[1].entries[2].frame
    local buttonRan, titleRan = hookAll(button, both()), hookAll(title, FRAME_SCRIPTS)
    dd:GenerateMenu()
    A.eq(w.menus[1].entries[1].frame, button)
    fireAll(w, button, both())
    fireAll(w, title, FRAME_SCRIPTS)
    A.same(buttonRan, {})
    A.same(titleRan, {})
  end)
end

local function test_a_refresh_drops_initializer_hooks_and_keeps_frame_script_hooks()
  withFrameXML("retail", function(w)
    local picks = 0
    HM.open(function(_, root)
      root:CreateButton("Go", function()
        picks = picks + 1
      end)
      root:CreateCheckbox("C", function()
        return false
      end, noop)
    end)
    local button = w.menus[1].entries[1].frame
    local ran = hookAll(button, both())
    HM.click(w, 1, 2) -- a checkbox answers Refresh (M8)
    fireAll(w, button, both())
    A.same(ran, { OnMouseDown = true, OnEnter = true, OnLeave = true })
    A.eq(picks, 1) -- the kit's OnClick, set again, still picks
  end)
end

-- A title is a Frame in the client (M18), so no initializer gives it an OnClick, on render or on Refresh.
local function test_a_refresh_gives_a_title_no_click()
  withFrameXML("retail", function(w)
    HM.open(function(_, root)
      root:CreateTitle("Title")
      root:CreateCheckbox("C", function()
        return false
      end, noop)
    end)
    local title = w.menus[1].entries[1].frame
    HM.click(w, 1, 2)
    A.eq(title:GetScript("OnClick"), nil)
  end)
end

-- A response other than CloseAll re-initializes every shallower level too (Menu.lua:2259-2262).
local function test_a_submenu_refresh_drops_the_parent_levels_click_hooks()
  withFrameXML("retail", function(w)
    HM.open(function(_, root)
      local parent = root:CreateButton("More", noop)
      parent:CreateCheckbox("C", function()
        return false
      end, noop)
    end)
    local parent = w.menus[1].entries[1].frame
    local ran = hookAll(parent, INITIALIZER_SCRIPTS)
    w.menus[1].enter(1)
    HM.click(w, 2, 1)
    fireAll(w, parent, INITIALIZER_SCRIPTS)
    A.same(ran, {})
  end)
end

-- ButtonInitializer sets OnDisable before ButtonFinalInitializer's SetEnabled (MenuTemplates.lua:109-113), so an
-- addon's OnDisable is gone before the refresh disables the button.
local function test_a_refresh_drops_on_disable_before_it_disables_the_button()
  withFrameXML("retail", function(w)
    local enabled, disables = true, 0
    HM.open(function(_, root)
      local go = root:CreateButton("Go", noop)
      go:SetEnabled(function()
        return enabled
      end)
      root:CreateCheckbox("C", function()
        return false
      end, function()
        enabled = false
      end)
    end)
    local button = w.menus[1].entries[1].frame
    button:SetScript("OnDisable", function()
      disables = disables + 1
    end)
    HM.click(w, 1, 2)
    A.eq(button:IsEnabled(), false)
    A.eq(disables, 0)
  end)
end

-- A pooled button that a re-render reuses for a title loses the kit's OnClick: a title is a Frame (M18).
local function test_a_rerender_that_turns_a_button_into_a_title_clears_its_click()
  withFrameXML("retail", function(w)
    local asTitle = false
    local dd = HM.newDropdownButton(function(_, root)
      if asTitle then
        root:CreateTitle("Go")
      else
        root:CreateButton("Go", noop)
      end
    end)
    dd:OpenMenu()
    local button = w.menus[1].entries[1].frame
    asTitle = true
    dd:GenerateMenu()
    A.eq(w.menus[1].entries[1].frame, button)
    A.eq(button:GetScript("OnClick"), nil)
  end)
end

return function()
  test_a_rerender_drops_hooks_on_every_script_it_sets()
  test_a_refresh_drops_initializer_hooks_and_keeps_frame_script_hooks()
  test_a_refresh_gives_a_title_no_click()
  test_a_submenu_refresh_drops_the_parent_levels_click_hooks()
  test_a_refresh_drops_on_disable_before_it_disables_the_button()
  test_a_rerender_that_turns_a_button_into_a_title_clears_its_click()
end

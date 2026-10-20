-- DropdownButton: the intrinsic widget type of the Menu API (registered per world, so only worlds that have the Menu API
-- fake know it). It opens a Menu API menu from a generator; a WowStyle1DropdownTemplate frame also shows the selection or
-- a default text in its Text child. Sources: docs/client-sources.md "DropdownButton and attributes" (D1-D10); client
-- paths are relative to
-- Interface/AddOns/Blizzard_Menu/.
local M = {}

local MenuDescription = require("framexml.fakes.menu_description")
local MenuFrames = require("framexml.fakes.menu_frames")
local MenuPick = require("framexml.fakes.menu_pick")
local Widgets = require("ui.widgets")

-- source: confirmed (row D3) DropdownButton.lua:83 registers the left button for mouse down only.
local OPEN_BUTTON = "LeftButton"
-- The template's FontString for the value text (row D7).
local TEXT_KEY = "Text"
-- LIST_DELIMITER, the client's global string joining several selected texts (MenuTemplates.lua:789).
local LIST_DELIMITER = ", "
-- The template's mixin global (row D7, Mainline/MenuTemplates.xml:3), which holds the value-text methods (row D10).
local MIXIN_NAME = "WowStyle1DropdownMixin"
local NO_GATE = { gate = "none" }

local methods = {}

local function isOpen(w, obj)
  return w.menus[1] ~= nil and w.menus[1].owner == obj
end

-- Writes the shown text (self.text or self.defaultText, MenuTemplates.lua:687-688, :730-732) to the Text child, when the
-- frame has one.
local function showText(w, obj, d)
  local child = obj[TEXT_KEY]
  if child and w.ui.state[child] then
    child:SetText(d.text or d.defaultText)
  end
end

-- Texts of every selected radio or checkbox under node, in tree order (MenuUtil.lua:63-67, :76-81).
local function collectSelected(w, node, out)
  for _, child in ipairs(node.children) do
    local _, checked = MenuPick.readState(w, child)
    if checked then
      out[#out + 1] = child.text
    end
    collectSelected(w, child, out)
  end
end

-- True when the frame got the template's mixin; a plain DropdownButton's UpdateToMenuSelections does nothing
-- (row D10, DropdownButton.lua:334-339).
local function hasSelectionText(w, obj)
  for _, name in ipairs(w.ui.state[obj].mixins or {}) do
    if name == MIXIN_NAME then
      return true
    end
  end
  return false
end

-- source: confirmed (row D6) MenuTemplates.lua:760-795 (UpdateToMenuSelections): after OverrideText nothing follows the
-- selection; else the selected texts joined, else the default text. d.root is the description the selection is read from.
local function updateSelection(w, obj, d)
  if d.overridden or not hasSelectionText(w, obj) then
    return
  end
  local selected = {}
  if d.root then
    collectSelected(w, d.root, selected)
  end
  d.text = #selected > 0 and table.concat(selected, LIST_DELIMITER) or d.defaultText
  showText(w, obj, d)
end

local generate

-- The menu opened for obj reports picks back: a response re-reads the selection, also after the menu closed
-- (DropdownButton.lua:279-288, SignalUpdate), or runs the generator again after EnableRegenerateOnResponse (row D9,
-- :290-300).
local function watch(w, obj, d)
  local state = w.menus[1].state
  d.root = state.root
  state.onUpdate = function()
    if d.regenerateOnResponse then
      generate(w, obj, d)
      return
    end
    d.root = state.root
    updateSelection(w, obj, d)
  end
end

-- source: confirmed (row D5) DropdownButton.lua:255-264: a generator always runs; an open menu is rebuilt in place, a
-- closed one gets a throwaway root. The open menu takes the current generator first, since SetupMenu may have replaced
-- it (:239, :195-201: the open menu gets the description the new generator built).
function generate(w, obj, d)
  if not d.generator then
    return
  end
  if isOpen(w, obj) then
    w.menus[1].state.generator = d.generator
    w.menus[1].rebuild()
    d.root = w.menus[1].state.root
  else
    d.root = MenuDescription.newRoot()
    w:callAsAddon(d.generator, obj, d.root)
  end
  updateSelection(w, obj, d)
end

-- source: confirmed (row D1) DropdownButton.xml:3-17 has OnMouseDown and no OnClick; (rows D2, D3) DropdownButton.lua:100-106,
-- :83: a left mouse down closes an open menu and opens a closed one. Held-Shift (:101-103) is not read: the kit has no key state.
local function onMouseDown(_, obj, _, button)
  if button ~= OPEN_BUTTON then
    return
  end
  if obj:IsMenuOpen() then
    obj:CloseMenu()
  else
    obj:OpenMenu()
  end
end

-- KeyValues of the intrinsic (row D7, DropdownButton.xml:4-10); the state of the dropdown lives in st.dropdown.
function methods.init(_, obj, st)
  st.dropdown = {}
  obj.intrinsic = "DropdownButton"
  obj.menuPoint = "TOPLEFT"
  obj.menuPointX = 0
  obj.menuPointY = 0
  obj.menuRelativePoint = "BOTTOMLEFT"
end

methods.scripts = { OnMouseDown = onMouseDown }

-- source: confirmed (row D5) DropdownButton.lua:237-249: stores the generator and, when shown, generates at once.
function methods.SetupMenu(w, obj, st, generator)
  st.dropdown.generator = generator
  if obj:IsShown() then
    generate(w, obj, st.dropdown)
  end
end

function methods.GenerateMenu(w, obj, st)
  generate(w, obj, st.dropdown)
end

function methods.IsMenuOpen(w, obj)
  return isOpen(w, obj)
end

function methods.CloseMenu(w, obj, st)
  if isOpen(w, obj) then
    st.dropdown.root = w.menus[1].state.root
    MenuFrames.close(w, 1)
  end
  updateSelection(w, obj, st.dropdown)
end

-- source: confirmed (row D2) DropdownButton.lua:143-149.
function methods.SetMenuOpen(_, obj, _, open)
  if open then
    obj:OpenMenu()
  else
    obj:CloseMenu()
  end
end

-- source: confirmed (row D9) DropdownButton.lua:279-288, :330-332: re-reads the selection of the last description; the
-- generator does not run. The OnUpdate callback event is not modelled.
function methods.SignalUpdate(w, obj, st)
  updateSelection(w, obj, st.dropdown)
end

methods.Update = methods.SignalUpdate

-- source: confirmed (row D9) DropdownButton.lua:221-231: the last generated root, nil before any; HasElements is false
-- without one.
function methods.GetMenuDescription(_, _, st)
  return st.dropdown.root
end

function methods.HasElements(_, _, st)
  local root = st.dropdown.root
  return root ~= nil and #root.children > 0
end

-- source: confirmed (row D9) DropdownButton.lua:210-215: forgets the description and the generator, then closes the
-- menu, whose update finds no selection.
function methods.ClearMenuState(w, obj, st)
  local d = st.dropdown
  d.generator, d.root = nil, nil
  if isOpen(w, obj) then
    MenuFrames.close(w, 1)
  end
  updateSelection(w, obj, d)
end

function methods.EnableRegenerateOnResponse(_, _, st)
  st.dropdown.regenerateOnResponse = true
end

-- source: confirmed (row D10) MenuTemplates.lua:929: WowStyle1DropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin,
-- DropdownSelectionTextMixin). The template copies it onto the frame, so its text methods shadow Button:SetText and
-- :GetText on template frames only. Only the value-text methods are modelled.
local function newMixin(w)
  local function dropdownOf(frame)
    return w.ui.state[frame].dropdown
  end
  local mixin = {}
  -- source: confirmed (row D6) MenuTemplates.lua:674-681.
  function mixin.GetText(self)
    return dropdownOf(self).text
  end
  function mixin.SetText(self, text)
    local d = dropdownOf(self)
    d.text = text
    showText(w, self, d)
  end
  -- source: confirmed (rows D6, D9) MenuTemplates.lua:734-741.
  function mixin.GetDefaultText(self)
    return dropdownOf(self).defaultText
  end
  function mixin.SetDefaultText(self, text)
    local d = dropdownOf(self)
    d.defaultText = text
    showText(w, self, d)
  end
  -- source: confirmed (row D6) MenuTemplates.lua:751-758: nil does nothing; else the text sticks over the selection.
  function mixin.OverrideText(self, text)
    if text == nil then
      return
    end
    dropdownOf(self).overridden = true
    self:SetText(text)
  end
  -- source: confirmed (row D5) MenuTemplates.lua:816-820, the template's <OnShow method="OnShow"/>.
  function mixin.OnShow(self)
    self:GenerateMenu()
  end
  return mixin
end

-- openMenu(w, owner, generator) -> menu frame|nil (framexml/fakes/menu.lua M.open).
function M.install(w, openMenu)
  w:install(MIXIN_NAME, newMixin(w), NO_GATE)
  local all = {}
  for key, fn in pairs(methods) do
    all[key] = fn
  end
  -- source: confirmed (row D5) DropdownButton.lua:107-130: nothing on a disabled dropdown or an open menu; the open runs
  -- the generator once.
  all.OpenMenu = function(world, obj, st)
    local d = st.dropdown
    if not obj:IsEnabled() or isOpen(world, obj) or not d.generator then
      return
    end
    if openMenu(world, obj, d.generator) then
      watch(world, obj, d)
    end
    updateSelection(world, obj, d)
  end
  Widgets.registerIntrinsic(w, "DropdownButton", "Button", all)
end

return M

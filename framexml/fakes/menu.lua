-- Menu API fake (MenuApi): MenuUtil.CreateContextMenu renders a description tree as MenuFrames levels; picks and
-- MenuResponse live in menu_pick.lua. Menu API levels are unnamed frames under UIParent.
-- Sources: docs/specs/2026-10-19-input-steps-sources.md "Phase 4" (M5-M7, M9, M10); client paths are relative to
-- Interface/AddOns/Blizzard_Menu/.
local M = {}

local MenuDescription = require("framexml.fakes.menu_description")
local MenuFrames = require("framexml.fakes.menu_frames")
local MenuPick = require("framexml.fakes.menu_pick")

local GATE_KEY = "MenuUtil.CreateContextMenu"
local NO_GATE = { gate = "none" }
local UNIT_TAG_PREFIX = "MENU_UNIT_"
local UNIT_NOTE = "Blizzard's own entries are not simulated"

local function copyTable(source)
  local copy = {}
  for key, value in pairs(source) do
    copy[key] = value
  end

  return copy
end

-- A fresh root, filled by generator(owner, root, ...) under addon context, then by every ModifyMenu hook stored for the
-- root's tag, in registration order: hook(owner, root, root.contextData) (M10, Menu.lua:2634-2637, :2646,2654). An error
-- is recorded and the menu opens with what was built so far; the remaining hooks still run. The client also calls a new
-- hook at once on the last menu with that tag (:2642-2646); the kit does not.
-- grug: open the partial menu; the client's behavior here is unsourced
local function runGenerator(w, state)
  local root = MenuDescription.newRoot()
  if state.tag then
    root:SetTag(state.tag, state.contextData)
  end
  w:callAsAddon(state.generator, state.owner, root, unpack(state.args, 1, state.args.n))
  local hooks = root.tag and w.menuApi.modifiers[root.tag]
  for _, hook in ipairs(hooks or {}) do
    w:callAsAddon(hook, state.owner, root, root.contextData)
  end

  return root
end

-- M6 (Menu.lua:1824-1826, :1966-2010): Close() closes this level and deeper while the level is open; a replaced or
-- closed level does nothing.
local function attachClose(w, level)
  level.frame.Close = function()
    local depth = MenuPick.depthOf(w, level)
    if depth then
      MenuFrames.close(w, depth)
    end
  end
end

local buildLevel

-- Opens the submenu of entry index at depth + 1; an entry without children, or a submenu already open, does nothing.
local function openSubmenu(w, level, index)
  local child = level.node.children[index]
  local open = w.menus[level.depth + 1]
  if not child or #child.children == 0 or (open and open.parentIndex == index and open.state == level.state) then
    return
  end
  local sub = buildLevel(w, level.state, child, level.depth + 1, index)
  MenuFrames.open(w, sub.depth, sub)
  attachClose(w, sub)
end

-- One level of the open menu: an entry per child of node, with enabled/checked read now (M2, M4).
function buildLevel(w, state, node, depth, parentIndex)
  local level = { entries = {}, owner = state.owner, parentIndex = parentIndex, state = state, depth = depth, node = node }
  for index, child in ipairs(node.children) do
    local enabled, checked = MenuPick.readState(w, child)
    level.entries[index] = { kind = child.kind, text = child.text, enabled = enabled, checked = checked, hasSubmenu = #child.children > 0 }
  end
  level.pick = MenuPick.forLevel(w, level)
  level.openSubmenu = function(index)
    openSubmenu(w, level, index)
  end
  level.rebuild = state.refresh

  return level
end

-- Re-runs the generator and re-renders every open level of this state in place (frames are reused): each level's node
-- is found again by walking the parent-index path from the new root. Levels whose node is gone close. A closed or
-- replaced menu does nothing (the generator does not run).
local function refresh(w, state)
  local old = {}
  for _, level in ipairs(w.menus) do
    if level.state == state then
      old[#old + 1] = level
    end
  end
  if #old == 0 then
    return
  end
  local node = runGenerator(w, state)
  state.root = node
  for _, previous in ipairs(old) do
    if previous.parentIndex then
      node = node.children[previous.parentIndex]
    end
    if not node or #node.children == 0 then
      MenuFrames.close(w, previous.depth)

      return
    end
    local level = buildLevel(w, state, node, previous.depth, previous.parentIndex)
    level.frame = previous.frame
    MenuFrames.open(w, level.depth, level)
    attachClose(w, level)
  end
end

-- Generator first, then the old menu closes (MenuUtil.lua:157-161, Menu.lua:2483-2493). An empty root opens nothing
-- unless allowEmpty, but the old menu is closed all the same (Menu.lua:2357-2361). Returns level 1's menu object (its
-- container frame), or nil.
local function openState(w, state, allowEmpty)
  state.root = runGenerator(w, state)
  if #state.root.children == 0 and not allowEmpty then
    MenuFrames.close(w, 1)
    return nil
  end
  state.refresh = function()
    refresh(w, state)
  end
  local level = buildLevel(w, state, state.root, 1, nil)
  MenuFrames.open(w, 1, level)
  attachClose(w, level)

  return level.frame
end

-- extra arguments go to the generator after (owner, root).
function M.open(w, owner, generator, tag, contextData, ...)
  local state = {
    owner = owner,
    generator = generator,
    tag = tag,
    contextData = contextData,
    args = { n = select("#", ...), ... },
  }

  return openState(w, state, false)
end

-- M9 (assumed: Blizzard_UnitPopup is not in the mirror): UnitPopup_OpenMenu(which, contextData) opens the tag
-- "MENU_UNIT_" .. which on a fresh unnamed Frame under UIParent. In the client the root holds Blizzard's own entries, which
-- the kit does not simulate, so the menu opens even when no hook adds anything. Called only from the installed global,
-- so error level 3 blames the addon's line.
local function openUnitPopup(w, which, contextData)
  if type(which) ~= "string" then
    error("UnitPopup_OpenMenu: which must be a string", 3)
  end
  local state = {
    owner = w.ui.create("Frame", nil, _G.UIParent),
    generator = function() end,
    tag = UNIT_TAG_PREFIX .. which,
    contextData = contextData,
    args = { n = 0 },
  }
  openState(w, state, true)
  for _, note in ipairs(w.notes) do
    if note == UNIT_NOTE then
      return
    end
  end
  w.notes[#w.notes + 1] = UNIT_NOTE
end

-- M10 (Menu.lua:2639-2660): stores fn under tag; nothing is returned (the client returns a handle). Called only from
-- the installed Menu.ModifyMenu, so error level 3 blames the addon's line.
local function modifyMenu(w, tag, fn)
  if type(tag) ~= "string" or type(fn) ~= "function" then
    error("Menu.ModifyMenu: tag must be a string and fn a function", 3)
  end
  local list = w.menuApi.modifiers[tag] or {}
  w.menuApi.modifiers[tag] = list
  list[#list + 1] = fn
end

function M.install(w)
  if not w.globals.framexml[GATE_KEY] then
    return
  end
  w.menuApi = { modifiers = {} }
  if w.globals.framexml.UnitPopup_OpenMenu then
    w:install("UnitPopup_OpenMenu", function(which, contextData)
      openUnitPopup(w, which, contextData)
    end, NO_GATE)
  end
  w:install("Menu", {
    ModifyMenu = function(tag, fn)
      modifyMenu(w, tag, fn)
    end,
  }, NO_GATE)
  w:install("MenuUtil", {
    -- MenuUtil.lua:152-155: a nil owner becomes GetAppropriateTopLevelParent(), which is UIParent in the game.
    CreateContextMenu = function(owner, generator, ...)
      return M.open(w, owner or _G.UIParent, generator, nil, nil, ...)
    end,
  }, NO_GATE)
  w:install("MenuResponse", copyTable(MenuPick.RESPONSE), NO_GATE)
  w:install("MenuInputContext", copyTable(MenuPick.INPUT_CONTEXT), NO_GATE)
  require("framexml.fakes.menu_dropdown").install(w, M.open)
end

return M

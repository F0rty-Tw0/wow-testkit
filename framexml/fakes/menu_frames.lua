-- Menu frames: renders a menu level (list of entries) into real Button frames and tracks the open levels in w.menus.
-- UIDropDownMenu levels use Blizzard's DropDownList<L> names; Menu API levels are unnamed frames under UIParent.
local M = {}

local Core = require("framexml.fakes.core")

local maxn = table.maxn

local MAX_LEVELS = 3
-- S9 (assumed): the shipped DropDownList frames come from UIDropDownMenu.xml, which the mirror does not hold; the
-- same template makes them Buttons. Mainline Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenu.lua:345
-- builds extra lists with CreateFrame("Button", "DropDownList"..n, nil, "UIDropDownListTemplate").
local LIST_TYPE = "Button"
-- M18: Menu API kinds whose client element is a Frame, not a Button (MenuTemplates.lua:276-292, :528-534).
local FRAME_KINDS = { title = true, divider = true }
M.FRAME_KINDS = FRAME_KINDS

-- The frame that holds the level's entries: DropDownList<L> by name, else a fresh unnamed Frame under UIParent.
local function containerFor(w, level)
  if level.frame then
    return level.frame
  end
  if level.namePrefix then
    return _G[level.namePrefix]
  end
  return w.ui.create("Frame", nil, _G.UIParent)
end

-- Entry i's Button: reused from the container's pool, else created (named <namePrefix>Button<i> when the level has a
-- prefix). The second result is true when the Button was just created.
local function buttonAt(w, level, container, index)
  local pool = w.menuPool[container]
  if not pool then
    pool = {}
    w.menuPool[container] = pool
  end
  if pool[index] then
    return pool[index], false
  end
  local name = level.namePrefix and (level.namePrefix .. "Button" .. index)
  local button = w.ui.create("Button", name, container)
  button.NormalText = button:CreateFontString(name and (name .. "NormalText"))
  pool[index] = button
  return button, true
end

-- The level's position in w.menus, or nil when it is not open.
local function depthOf(w, level)
  for depth = 1, maxn(w.menus) do
    if w.menus[depth] == level then
      return depth
    end
  end
  return nil
end

-- S11: a disabled entry's enter only closes deeper levels: the client covers it with an InvisibleButton whose OnEnter
-- closes depth + 1 (Mainline UIDropDownMenu.lua:153-154, :471-475; Classic :180-182, :423-426). A Menu API level brings
-- its own rule as level.enter (framexml/fakes/menu.lua, M14).
local function enterEntry(w, level, entry, index)
  if level.enter then
    level.enter(index)
    return
  end
  local depth = depthOf(w, level)
  if entry.hasSubmenu and entry.enabled ~= false then
    level.openSubmenu(index)
  elseif depth then
    M.close(w, depth + 1)
  end
end

-- Kit scripts for one Button, set through the world so an addon's SetScript replaces them. They act on the entry the
-- Button shows when they run (w.menuBound).
local function setBoundScripts(w, button)
  w:setScript(button, "OnClick", function(_, mouseButton)
    local bound = w.menuBound[button]
    bound.level.pick(bound.index, mouseButton)
  end)
  w:setScript(button, "OnEnter", function()
    local bound = w.menuBound[button]
    enterEntry(w, bound.level, bound.entry, bound.index)
  end)
end

-- S21: a UIDropDownMenu Button (named level) gets its scripts once, when created, as UIDropDownMenuButtonTemplate sets
-- them; it is a disabled Button whose InvisibleButton takes the enter (S11). A Menu API element gets OnEnter on every
-- render (Menu.lua:1128-1130), which enables its mouse (I5); a title or divider is a Frame there, so it has no OnClick
-- (M18).
local function setEntryScripts(w, level, entry, button, created)
  if level.namePrefix and not created then
    return
  end
  button:EnableMouse(true)
  setBoundScripts(w, button)
  if not level.namePrefix and FRAME_KINDS[entry.kind] then
    w:setScript(button, "OnClick", nil)
  end
end

local function fillButton(w, level, entry, index, button, created)
  button.NormalText:SetText(entry.text or "")
  if entry.enabled == false then
    button:Disable()
  else
    button:Enable()
  end
  w.menuBound[button] = { level = level, entry = entry, index = index }
  setEntryScripts(w, level, entry, button, created)
  button:Show()
  entry.frame = button
end

-- Renders entry index of level into its Button alone: sets level.frame and the entry's frame.
function M.renderEntry(w, level, index)
  local container = containerFor(w, level)
  level.frame = container
  local button, created = buttonAt(w, level, container, index)
  fillButton(w, level, level.entries[index], index, button, created)
end

-- Renders level into frames: sets level.frame and each entry.frame; buttons past the entry count are hidden.
function M.render(w, level)
  for index = 1, #level.entries do
    M.renderEntry(w, level, index)
  end
  local container = containerFor(w, level)
  level.frame = container
  for index = #level.entries + 1, #(w.menuPool[container] or {}) do
    w.menuPool[container][index]:Hide()
  end
end

-- True when focus is the container or one of its descendants.
local function focusInside(focus, container)
  local current = focus
  while current do
    if current == container then
      return true
    end
    current = current:GetParent()
  end
  return false
end

-- S3 (assumed): hiding a shown frame under the cursor fires its OnLeave (Interface/AddOns/Blizzard_Menu/Menu.lua:1077,
-- "causing the OnLeave to be called"); motion = false because a hide is not mouse movement (wiki UIHANDLER_OnLeave).
-- The focus clears before OnLeave runs, as Input.leave does.
local function hideLevel(w, level)
  local container = level.frame
  container:Hide()
  local focus = w.input.mouseFocus
  if focus and focusInside(focus, container) then
    w.input.mouseFocus = nil
    w:callScript(focus, "OnLeave", false)
  end
end

-- Closes level depth and every deeper level, deepest first. Each level leaves w.menus before its OnLeave runs, so a
-- handler that closes menus itself sees only the levels still open. maxn, not #: w.menus can have gaps (open).
function M.close(w, depth)
  while maxn(w.menus) >= depth do
    local last = maxn(w.menus)
    local level = w.menus[last]
    w.menus[last] = nil
    hideLevel(w, level)
  end
end

-- Opens level at depth (1 is the first menu): closes it and deeper levels first, then renders and shows it. The
-- shallower levels may be closed: ToggleDropDownMenu shows DropDownList<n> without looking at the lists below it
-- (Mainline Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenu.lua:1049-1202, Classic :990-1139).
function M.open(w, depth, level)
  M.close(w, depth)
  w.menus[depth] = level
  M.render(w, level)
  level.frame:Show()
end

function M.install(w)
  w.menus = {}
  w.notes = {}
  w.menuPool = {}
  w.menuBound = setmetatable({}, { __mode = "k" })
  for i = 1, MAX_LEVELS do
    local list = Core.createNamed(w, LIST_TYPE, "DropDownList" .. i, _G.UIParent)
    if list then
      list:Hide()
    end
  end
end

return M

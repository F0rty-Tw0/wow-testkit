-- Scenario menu steps: menu (what is open), pick (enter down a path, click the last entry), openMenu and closeMenus.
local M = {}

local Input = require("input")
local MenuFrames = require("framexml.fakes.menu_frames")

local ENGINE = "blizzard"
local PICK_BUTTON = "LeftButton"

-- The text without color escapes (|cAARRGGBB and |r).
local function stripEscapes(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function copyEntry(entry)
  return {
    kind = entry.kind,
    text = entry.text,
    enabled = entry.enabled,
    checked = entry.checked,
    hasSubmenu = entry.hasSubmenu,
    frame = entry.frame,
  }
end

local function copyLevel(level)
  local entries = {}
  for i, entry in ipairs(level.entries) do
    entries[i] = copyEntry(entry)
  end
  return { parentIndex = level.parentIndex, entries = entries }
end

-- Stripped entry texts of a level, comma separated (entries without text are skipped).
local function strippedTexts(level)
  local texts = {}
  for _, entry in ipairs(level.entries) do
    if entry.text then
      texts[#texts + 1] = stripEscapes(entry.text)
    end
  end
  return table.concat(texts, ", ")
end

-- The entry of level whose stripped text is text, and its index; or nil and the problem.
local function findEntry(level, text, depth)
  local matches = {}
  for index, entry in ipairs(level.entries) do
    if entry.text and stripEscapes(entry.text) == text then
      matches[#matches + 1] = index
    end
  end
  local count = #matches
  if count == 1 then
    return level.entries[matches[1]], matches[1]
  end
  local listing = "; entries: " .. strippedTexts(level)
  if count == 0 then
    return nil, nil, string.format('no entry "%s" in level %d', text, depth) .. listing
  end
  return nil, nil, string.format('%d entries match "%s" in level %d', count, text, depth) .. listing
end

-- The entry for path element depth, or nil and the problem; previous is the entry entered at depth - 1.
local function locate(w, text, depth, previous)
  local level = w.menus[depth]
  if not level or (previous and level.parentIndex ~= previous.index) then
    return nil, nil, '"' .. previous.text .. '" has no submenu'
  end
  return findEntry(level, text, depth)
end

-- Enters (not last) or left-clicks (last) the frame under engine context; a blocked action throws "pick: <reason>". A
-- last entry with no OnClick (a Menu API title or divider, M18) throws too, since the click would do nothing.
local function act(w, frame, text, isLast)
  local reason = Input.blockedReason(w, frame, isLast and "click" or "enter")
  if reason then
    error("pick: " .. reason, 3)
  end
  if isLast and not w:getScript(frame, "OnClick") then
    error('pick: "' .. text .. '" has no click', 3)
  end
  if isLast then
    w:run(ENGINE, Input.click, w, frame, PICK_BUTTON)
  else
    w:run(ENGINE, Input.enter, w, frame)
  end
end

function M.extend(Scenario)
  function Scenario:menu()
    local levels = {}
    for i, level in ipairs(self.w.menus) do
      levels[i] = copyLevel(level)
    end
    if #levels == 0 then
      return nil
    end
    return { kind = "menu", levels = levels }
  end

  function Scenario:pick(textOrPath)
    local w = self.w
    local kind = type(textOrPath)
    if kind ~= "string" and kind ~= "table" then
      error("pick: expected an entry text or a path table, got " .. kind, 2)
    end
    -- Paths start at level 1; a list shown above a closed level 1 leaves a hole that # may not see.
    if not w.menus[1] then
      error("pick: no menu is open", 2)
    end
    local path = type(textOrPath) == "string" and { textOrPath } or textOrPath
    if #path == 0 then
      error("pick: empty path", 2)
    end
    local previous
    for depth, text in ipairs(path) do
      local entry, index, problem = locate(w, text, depth, previous)
      if problem then
        error("pick: " .. problem, 2)
      end
      act(w, entry.frame, text, depth == #path)
      previous = { text = text, index = index }
    end
  end

  -- Calls UnitPopup_OpenMenu(which, contextData) under engine context (the unit popup menu of a player row). which is
  -- checked here: the global's own error would land on w:run's pcall and name no line of the scenario.
  function Scenario:openMenu(which, contextData)
    local open = rawget(_G, "UnitPopup_OpenMenu")
    if not open then
      error("openMenu: UnitPopup_OpenMenu is not on " .. self.flavor, 2)
    end
    if type(which) ~= "string" then
      error("openMenu: which must be a string, got " .. type(which), 2)
    end
    self.w:run(ENGINE, open, which, contextData)
  end

  function Scenario:closeMenus()
    self.w:run(ENGINE, MenuFrames.close, self.w, 1)
  end
end

return M

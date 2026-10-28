-- The Edit Mode caches of a WTF folder. The account file (edit-mode-cache-account.txt) is one line of words split by
-- single spaces (a word may be empty): `<version> <n> <n account settings>` then, per saved layout, `<name length>
-- <name> <count>` (the name is that many bytes and may hold spaces) and count systems: `<system> <systemIndex>
-- <isInDefaultPosition 0|1> <anchor> <second anchor | -1> <settings>`, an anchor being `<point> <relativePoint>
-- <relativeTo> <offsetX> <offsetY>`. The character file (edit-mode-cache-character.txt) is `<version>` and one active
-- layout per specialization slot; the words some files hold after the slots (character layouts) are not read. Both end
-- in a NUL.
local M = {}

local EditMode = require("game.editmode")

-- source: assumed (row BU6) the anchor point numbers follow the FramePoint enum order.
local POINTS = { [0] = "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local NO_SECOND_ANCHOR = "-1"
-- source: assumed (row BU6) the account file holds no layout type; its layouts are Enum.EditModeLayoutType.Account.
local ACCOUNT_LAYOUT = 1

local function words(text)
  local out, start = {}, 1
  local trimmed = text:gsub("%z+$", "")
  repeat
    local stop = trimmed:find(" ", start, true)
    out[#out + 1] = trimmed:sub(start, (stop or 0) - 1)
    start = stop and stop + 1
  until not start

  return out
end

local function int(word)
  local whole = word and word:match("^%-?%d+$")

  return whole and tonumber(whole)
end

-- The anchorInfo whose five words start at t[i], or nil.
local function anchorAt(t, i)
  local point, relativePoint = POINTS[int(t[i])], POINTS[int(t[i + 1])]
  local offsetX, offsetY = tonumber(t[i + 3]), tonumber(t[i + 4])
  local readable = point and relativePoint and t[i + 2] and offsetX and offsetY
  if not readable then
    return nil
  end

  return { point = point, relativeTo = t[i + 2], relativePoint = relativePoint, offsetX = offsetX, offsetY = offsetY }
end

-- The system whose words start at t[i] and the index after it, or nil. Settings stay as their raw word (settingsRaw);
-- settings is empty.
local function systemAt(t, i)
  local system, index, default = int(t[i]), int(t[i + 1]), t[i + 2]
  local anchorInfo = anchorAt(t, i + 3)
  local second = t[i + 8] ~= NO_SECOND_ANCHOR and anchorAt(t, i + 8)
  local settingsAt = second and i + 13 or i + 9
  local placed = anchorInfo and (second or t[i + 8] == NO_SECOND_ANCHOR)
  local readable = system and index and (default == "0" or default == "1") and placed and t[settingsAt]
  if not readable then
    return nil
  end
  local systemIndex = index >= 0 and index or nil
  local info = { system = system, systemIndex = systemIndex, isInDefaultPosition = default == "1", anchorInfo = anchorInfo }
  info.anchorInfo2, info.settings, info.settingsRaw = second or nil, {}, t[settingsAt]

  return info, settingsAt + 1
end

-- The layout whose header starts at t[i] and the index after it, or nil.
local function layoutAt(t, i)
  local length, j = int(t[i]), i + 1
  local name = t[j]
  while length and name and #name < length do
    j = j + 1
    name = t[j] and name .. " " .. t[j]
  end
  local count = name and #name == length and int(t[j + 1])
  if not count then
    return nil
  end
  local layout = { layoutType = ACCOUNT_LAYOUT, layoutName = name, systems = {} }
  local at = j + 2
  for n = 1, count do
    layout.systems[n], at = systemAt(t, at)
    if not at then
      return nil
    end
  end

  return layout, at
end

-- The saved layouts of an account file's text (layoutInfo tables, see game/editmode.lua), or nil and why not.
function M.parseLayouts(text)
  local t = words(text)
  local n = int(t[2])
  if not (int(t[1]) and n and n >= 0 and #t >= n + 2) then
    return nil, "no version and account settings header"
  end
  local layouts, i = {}, n + 3
  while i <= #t do
    local layout, after = layoutAt(t, i)
    if not layout then
      return nil, "unreadable layout at word " .. i
    end
    layouts[#layouts + 1] = layout
    i = after
  end

  return layouts
end

-- source: assumed (row BU6) the first specialization slot is the active layout; the kit has no specialization.
-- The client's activeLayout (presets counted, row BU5) a character file's text names for count saved layouts, or nil
-- when it names none (-1) or one outside the list.
function M.parseActive(text, count)
  local active = int(words(text)[2])
  local valid = active and active >= 1 and active <= count + EditMode.PRESET_COUNT

  return valid and active or nil
end

return M

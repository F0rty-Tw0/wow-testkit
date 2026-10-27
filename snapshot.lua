-- Snapshots: a GameTooltip or a frame tree as stable text for golden files. Text is split into "[rrggbb]text"
-- runs: |cAARRGGBB pushes a color, |r pops one, |T<file>:...|t becomes [tex:<file>], || is a literal pipe; text
-- outside escapes takes the font string's own text color. Never contains file paths or line numbers.
local M = {}

local Secret = require("combat_secret_value")

local INDENT = "  "
local NO_VALUE = "-"
local COLOR_ESCAPE = "^|c%x%x(%x%x%x%x%x%x)"
local ESCAPE_LENGTH = { color = 10, pair = 2 }

local function channel(c)
  return string.format("%02x", math.floor((c or 0) * 255 + 0.5))
end

local function hex(r, g, b)
  return channel(r) .. channel(g) .. channel(b)
end

local function round(n)
  return math.floor((n or 0) + 0.5)
end

-- Appends piece in color, merging into the previous run when the color is the same.
local function append(runs, color, piece)
  if piece == "" then
    return
  end
  local last = runs[#runs]
  if last and last.color == color then
    last.text = last.text .. piece
  else
    runs[#runs + 1] = { color = color, text = piece }
  end
end

-- Handles the escape starting at pos (a "|"); returns the position after it.
local function escapeAt(text, pos, stack, runs)
  local color = stack[#stack]
  local rgb = text:match(COLOR_ESCAPE, pos)
  local code = text:sub(pos + 1, pos + 1)
  if rgb then
    stack[#stack + 1] = rgb:lower()
    return pos + ESCAPE_LENGTH.color
  elseif code == "r" then
    if #stack > 1 then
      stack[#stack] = nil
    end
    return pos + ESCAPE_LENGTH.pair
  elseif code == "|" then
    append(runs, color, "|")
    return pos + ESCAPE_LENGTH.pair
  elseif code == "T" then
    local close = text:find("|t", pos + 2, true)
    if close then
      append(runs, color, "[tex:" .. text:sub(pos + 2, close - 1):match("^[^:]*") .. "]")
      return close + ESCAPE_LENGTH.pair
    end
  end
  append(runs, color, "|")
  return pos + 1
end

-- text as "[rrggbb]text" runs, base being the color outside any escape.
function M.runs(text, base)
  local runs, stack, pos = {}, { base }, 1
  text = text or ""
  while pos <= #text do
    local bar = text:find("|", pos, true) or #text + 1
    append(runs, stack[#stack], text:sub(pos, bar - 1))
    pos = bar <= #text and escapeAt(text, bar, stack, runs) or bar
  end
  local out = {}
  for i, run in ipairs(runs) do
    out[i] = "[" .. run.color .. "]" .. run.text
  end
  return table.concat(out)
end

local function fontRuns(fontString)
  return M.runs(Secret.text(fontString:GetText()), hex(fontString:GetTextColor()))
end

-- One line per tooltip row ("L: <runs>", plus " | R: <runs>" for a non-empty right text), then the border color.
function M.tooltip(tip)
  local name, out = tip:GetName(), {}
  for i = 1, tip:NumLines() do
    local line = "L: " .. fontRuns(rawget(_G, name .. "TextLeft" .. i))
    local right = rawget(_G, name .. "TextRight" .. i)
    if right and right:IsShown() and (right:GetText() or "") ~= "" then
      line = line .. " | R: " .. fontRuns(right)
    end
    out[#out + 1] = line
  end
  local slice = tip.NineSlice
  local r, g, b
  if slice and slice.GetBorderColor then
    r, g, b = slice:GetBorderColor()
  end
  if r then
    out[#out + 1] = "border=" .. hex(r, g, b)
  end
  return table.concat(out, "\n")
end

local function present(value)
  return value ~= nil and value ~= "" and tostring(value) or nil
end

local function regionLine(region)
  local kind = region:GetObjectType()
  if kind == "FontString" then
    return 'FontString "' .. fontRuns(region) .. '"'
  elseif kind == "Texture" then
    local atlas = region.GetAtlas and region:GetAtlas()
    return "Texture " .. (present(region:GetTexture()) or present(atlas) or NO_VALUE)
  end
  return kind
end

-- Regions first, then child frames, each in the order they were parented; hidden ones are skipped.
local function walk(frame, depth, out)
  local indent = string.rep(INDENT, depth)
  local size = round(frame:GetWidth()) .. "x" .. round(frame:GetHeight())
  out[#out + 1] = string.format('%s%s "%s" %s', indent, frame:GetObjectType(), frame:GetName() or NO_VALUE, size)
  for _, region in ipairs({ frame:GetRegions() }) do
    if region:IsShown() then
      out[#out + 1] = indent .. INDENT .. regionLine(region)
    end
  end
  for _, child in ipairs({ frame:GetChildren() }) do
    if child:IsShown() then
      walk(child, depth + 1, out)
    end
  end
end

-- frame and its shown descendants as an indented tree (2 spaces per level).
function M.frame(frame)
  local out = {}
  walk(frame, 0, out)
  return table.concat(out, "\n")
end

-- Entries by kind: a check or radio mark before the text, "> " for a submenu, " (disabled)" after.
local MENU_TEXT_COLOR = "ffffff"
local MENU_MARKS = {
  checkbox = { [true] = "[x] ", [false] = "[ ] " },
  radio = { [true] = "(o) ", [false] = "( ) " },
}

local function menuLine(entry)
  local text = M.runs(entry.text, MENU_TEXT_COLOR)
  if entry.kind == "title" then
    return "== " .. text .. " =="
  elseif entry.kind == "divider" then
    return "---"
  end
  local marks = MENU_MARKS[entry.kind]
  local mark = marks and marks[entry.checked == true] or ""
  local submenu = entry.hasSubmenu and "> " or ""
  local disabled = entry.enabled == false and " (disabled)" or ""
  return mark .. submenu .. text .. disabled
end

local function emitMenu(levels, depth, out)
  local level = levels[depth]
  local below = levels[depth + 1]
  for i, entry in ipairs(level.entries) do
    out[#out + 1] = string.rep(INDENT, depth - 1) .. menuLine(entry)
    if below and below.parentIndex == i then
      emitMenu(levels, depth + 1, out)
    end
  end
end

-- value { kind = "menu", levels = { { parentIndex, entries }, ... } } as one line per entry, a level deeper
-- indented under the submenu entry that opened it.
function M.menu(value)
  local out = {}
  if value.levels[1] then
    emitMenu(value.levels, 1, out)
  end
  return table.concat(out, "\n")
end

return M

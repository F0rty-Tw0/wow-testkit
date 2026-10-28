-- Colour objects and colour globals: ColorMixin and CreateColor, the hex and byte constructors, WrapTextInColorCode,
-- GetClassColor, C_ClassColor.GetClassColor, the font colour globals and the standard font paths. The font colours
-- come out of C_UIColor.GetColors the way the client's colour file imports them (row W68). Kit-authored bodies over the
-- behaviour rows W68 and W69 record. CUSTOM_CLASS_COLORS (a colour addon's table) and ColorGradient (in no extract
-- and no api list) are not Blizzard globals, so neither is installed.
local M = {}

local Core = require("framexml.fakes.core")

-- Localized: addon code may assign globals named ipairs, pairs, tonumber or unpack.
local ipairs, pairs, tonumber, unpack = ipairs, pairs, tonumber, unpack
local format, floor = string.format, math.floor

local API_GATE = { gate = "api" }
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local BYTE_MAX = 255
local HEX_LENGTH = 8
local HEX_DIGITS = 2
local DEFAULT_ALPHA = 1
local UNKNOWN_CLASS_COLOR = { 1, 1, 1, "ffffffff" }
-- source: row W69 (confirmed) outside the koKR, zhCN, zhTW and ruRu locales; the row gives no path for those four, so
-- the kit uses this one for every locale (assumed).
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local FONT_GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "DAMAGE_TEXT_FONT" }

-- source: row W68 (confirmed: NORMAL, RED, GREEN, as `ffd200`, `ff2020`, `19ff19` literals; assumed: the rest, read from
-- the wiki list) the values C_UIColor.GetColors answers.
local UI_COLORS = {
  { baseTag = "NORMAL_FONT_COLOR", color = { r = 1, g = 0.824, b = 0, a = 1 } },
  { baseTag = "HIGHLIGHT_FONT_COLOR", color = { r = 1, g = 1, b = 1, a = 1 } },
  { baseTag = "WHITE_FONT_COLOR", color = { r = 1, g = 1, b = 1, a = 1 } },
  { baseTag = "GRAY_FONT_COLOR", color = { r = 0.502, g = 0.502, b = 0.502, a = 1 } },
  { baseTag = "LIGHTGRAY_FONT_COLOR", color = { r = 0.6, g = 0.6, b = 0.6, a = 1 } },
  { baseTag = "GREEN_FONT_COLOR", color = { r = 0.098, g = 1, b = 0.098, a = 1 } },
  { baseTag = "RED_FONT_COLOR", color = { r = 1, g = 0.125, b = 0.125, a = 1 } },
  { baseTag = "YELLOW_FONT_COLOR", color = { r = 1, g = 1, b = 0, a = 1 } },
}

local function byte(channel)
  return floor(channel * BYTE_MAX + 0.5)
end

-- source: blizzard_sharedxmlbase/color.lua:1-58 (the methods) and row W69.
local ColorMixin = {}

function ColorMixin:OnLoad(r, g, b, a)
  self:SetRGBA(r, g, b, a)
end

function ColorMixin:SetRGBA(r, g, b, a)
  self.r, self.g, self.b, self.a = r, g, b, a or DEFAULT_ALPHA
end

function ColorMixin:SetRGB(r, g, b)
  self:SetRGBA(r, g, b, nil)
end

function ColorMixin:GetRGB()
  return self.r, self.g, self.b
end

function ColorMixin:GetRGBA()
  return self.r, self.g, self.b, self.a
end

function ColorMixin:GetRGBAsBytes()
  return byte(self.r), byte(self.g), byte(self.b)
end

function ColorMixin:GetRGBAAsBytes()
  return byte(self.r), byte(self.g), byte(self.b), byte(self.a or DEFAULT_ALPHA)
end

function ColorMixin:IsRGBEqualTo(other)
  return self.r == other.r and self.g == other.g and self.b == other.b
end

function ColorMixin:IsEqualTo(other)
  return self:IsRGBEqualTo(other) and self.a == other.a
end

-- AARRGGBB in lower case, the form a |c escape takes after the two characters of the prefix. Blizzard's color.lua
-- builds GenerateHexColor and WrapTextInColorCode on C_ColorUtil, so the engine calls answer the same text.
-- source: row W76 (confirmed: the |c ... |r wrap; assumed: this hex form for the engine calls too).
local function textColorCode(color)
  return format("%02x%02x%02x%02x", byte(color.a or DEFAULT_ALPHA), byte(color.r), byte(color.g), byte(color.b))
end

function ColorMixin:GenerateHexColor()
  return textColorCode(self)
end

function ColorMixin:GenerateHexColorNoAlpha()
  return format("%02X%02X%02X", self:GetRGBAsBytes())
end

function ColorMixin:GenerateHexColorMarkup()
  return "|c" .. self:GenerateHexColor()
end

function ColorMixin:WrapTextInColorCode(text)
  return M.wrap(text, self:GenerateHexColor())
end

-- Copies the mixin's fields onto a new table, the way CreateFromMixins does.
function M.new(r, g, b, a)
  local color = {}
  for key, value in pairs(ColorMixin) do
    color[key] = value
  end
  color:OnLoad(r, g, b, a)

  return color
end

function M.wrap(text, hex)
  return "|c" .. hex .. text .. "|r"
end

local function channel(hex, first)
  return tonumber(hex:sub(first, first + HEX_DIGITS - 1), 16) / BYTE_MAX
end

-- source: row W69 (confirmed) needs 8 hex characters (AARRGGBB), else it asserts and returns nil. How the assertion
-- surfaces is assumed: the kit reports it to the error handler and goes on.
local function fromHexString(w)
  return function(hex)
    if #hex ~= HEX_LENGTH then
      w:reportError("CreateColorFromHexString input must be hexadecimal digits in this format: AARRGGBB.")
      return nil
    end

    return M.new(channel(hex, 3), channel(hex, 5), channel(hex, 7), channel(hex, 1))
  end
end

local function fromBytes(r, g, b, a)
  return M.new(r / BYTE_MAX, g / BYTE_MAX, b / BYTE_MAX, a / BYTE_MAX)
end

local function wrapInColor(text, color)
  return color:WrapTextInColorCode(text)
end

-- source: row W69 (confirmed) r, g, b, colorStr for a known class, else 1, 1, 1, "ffffffff".
local function classColor(classes)
  return function(classFile)
    local color = classes[classFile]
    if not color then
      return unpack(UNKNOWN_CLASS_COLOR)
    end

    return color.r, color.g, color.b, color.colorStr
  end
end

-- The object itself (assumed: the api types the answer as a colour table); nil for an unknown class (mayReturnNothing).
local function classColorObject(classes)
  return function(classFile)
    return classes[classFile]
  end
end

-- source: row W68 (confirmed) blizzard_sharedxmlbase/color.lua:82 reads C_UIColor.GetColors once and makes each entry a
-- colour global plus a `_CODE` string of its markup.
local function installUIColors(w, getColors)
  w:install("C_UIColor.GetColors", getColors, API_GATE)
  for _, entry in ipairs(getColors()) do
    local color = entry.color
    local object = M.new(color.r, color.g, color.b, color.a)
    w:install(entry.baseTag, object, Core.GATE)
    w:install(entry.baseTag .. "_CODE", object:GenerateHexColorMarkup(), Core.GATE)
  end
end

local function copyUIColors()
  local out = {}
  for i, entry in ipairs(UI_COLORS) do
    local color = entry.color
    out[i] = { baseTag = entry.baseTag, color = { r = color.r, g = color.g, b = color.b, a = color.a } }
  end

  return out
end

function M.install(w)
  w:install("ColorMixin", ColorMixin, Core.GATE)
  w:install("CreateColor", M.new, KETHO_GATE)
  w:install("CreateColorFromHexString", fromHexString(w), KETHO_GATE)
  w:install("CreateColorFromBytes", fromBytes, KETHO_GATE)
  w:install("WrapTextInColorCode", M.wrap, KETHO_GATE)
  w:install("WrapTextInColor", wrapInColor, KETHO_GATE)
  w:install("C_ColorUtil.GenerateTextColorCode", textColorCode, API_GATE)
  w:install("C_ColorUtil.WrapTextInColorCode", M.wrap, API_GATE)
  w:install("C_ColorUtil.WrapTextInColor", function(text, color)
    return M.wrap(text, textColorCode(color))
  end, API_GATE)
  local classes = rawget(_G, "RAID_CLASS_COLORS") or {}
  w:install("GetClassColor", classColor(classes), KETHO_GATE)
  w:install("C_ClassColor.GetClassColor", classColorObject(classes), API_GATE)
  installUIColors(w, copyUIColors)
  for _, name in ipairs(FONT_GLOBALS) do
    w:install(name, STANDARD_FONT, Core.GATE)
  end
end

return M

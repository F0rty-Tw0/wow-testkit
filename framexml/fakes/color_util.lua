-- Colour objects and colour globals: ColorMixin and CreateColor, the hex and byte constructors, WrapTextInColorCode,
-- GetClassColor, C_ClassColor.GetClassColor, the UI colour globals (font, tooltip and hotkey colours) and the standard
-- font paths. The UI colours come out of C_UIColor.GetColors the way the client's colour file imports them (row W68). Kit-authored bodies over the
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
  -- source: row W78 (confirmed) GlobalColor rows 29, 78, 79 (ARGB ffcccccc, ffffffff, ff171730); no Lua defines them.
  { baseTag = "ACTIONBAR_HOTKEY_FONT_COLOR", color = { r = 0.8, g = 0.8, b = 0.8, a = 1 } },
  { baseTag = "TOOLTIP_DEFAULT_COLOR", color = { r = 1, g = 1, b = 1, a = 1 } },
  { baseTag = "TOOLTIP_DEFAULT_BACKGROUND_COLOR", color = { r = 0.09, g = 0.09, b = 0.188, a = 1 } },
  -- source: row W83 (confirmed) GlobalColor rows 395-398 (RGB ffb300, 00ff00, b3b3b3, ff0000); the classic cast bar
  -- colours its fill with them (tbc 70577 blizzard_uipanels_game/shared/castingbarframe.lua:23-24, :628-630).
  { baseTag = "CASTBAR_CLASSIC_YELLOW", color = { r = 1, g = 179 / 255, b = 0, a = 1 } },
  { baseTag = "CASTBAR_CLASSIC_GREEN", color = { r = 0, g = 1, b = 0, a = 1 } },
  { baseTag = "CASTBAR_CLASSIC_GRAY", color = { r = 179 / 255, g = 179 / 255, b = 179 / 255, a = 1 } },
  { baseTag = "CASTBAR_CLASSIC_RED", color = { r = 1, g = 0, b = 0, a = 1 } },
  -- source: row W85 (confirmed) GlobalColor row 17 `-8355712` (ARGB ff808080); 9.2.7 Lua had 7f7f7f, but no Lua in the
  -- forever 70862 or tbc 70577 extract assigns it now.
  { baseTag = "DISABLED_FONT_COLOR", color = { r = 128 / 255, g = 128 / 255, b = 128 / 255, a = 1 } },
  -- source: row W86 (confirmed) GlobalColor row 191 `-870375903` (ARGB cc1f1e21); the bag frame's backdrop reads it
  -- (forever 70862 blizzard_sharedxml/portraitframe.lua:123); no extract Lua defines it.
  { baseTag = "PANEL_BACKGROUND_COLOR", color = { r = 31 / 255, g = 30 / 255, b = 33 / 255, a = 204 / 255 } },
  -- source: row W87 (confirmed) GlobalColor rows 63, 76, 77 (ARGB ff82c5ff, ffff2934, ff00adf0) and 406 (RGB ffd100,
  -- alpha assumed 1 as W83); no extract Lua defines them.
  { baseTag = "FRIENDS_BNET_NAME_COLOR", color = { r = 130 / 255, g = 197 / 255, b = 1, a = 1 } },
  { baseTag = "PLAYER_FACTION_COLOR_HORDE", color = { r = 1, g = 41 / 255, b = 52 / 255, a = 1 } },
  { baseTag = "PLAYER_FACTION_COLOR_ALLIANCE", color = { r = 0, g = 173 / 255, b = 240 / 255, a = 1 } },
  { baseTag = "UNIT_LEVEL_NON_ATTACKABLE", color = { r = 1, g = 209 / 255, b = 0, a = 1 } },
  -- source: row W88 (confirmed) GlobalColor rows 242-255 (ARGB in each comment); forever's UnitFrame_Initialize fills the
  -- mana cost prediction bar with POWERBAR_PREDICTION_COLOR_MANA (mainline/unitframe.lua:597-600) and unitframe.xml:5-15
  -- names the heal and absorb ones; no extract Lua defines them.
  { baseTag = "HEALTHBAR_MY_HEAL_PREDICTION_COLOR", color = { r = 0, g = 211 / 255, b = 195 / 255, a = 1 } }, -- ff00d3c3
  { baseTag = "HEALTHBAR_OTHER_HEAL_PREDICTION_COLOR", color = { r = 0, g = 161 / 255, b = 142 / 255, a = 1 } }, -- ff00a18e
  { baseTag = "HEALTHBAR_HEAL_ABSORB_COLOR", color = { r = 108 / 255, g = 166 / 255, b = 13 / 255, a = 1 } }, -- ff6ca60d
  { baseTag = "HEALTHBAR_TOTAL_ABSORB_COLOR", color = { r = 1, g = 1, b = 1, a = 1 } }, -- ffffffff
  { baseTag = "POWERBAR_PREDICTION_COLOR_MANA", color = { r = 0, g = 45 / 255, b = 104 / 255, a = 1 } }, -- ff002d68
  { baseTag = "POWERBAR_PREDICTION_COLOR_RAGE", color = { r = 102 / 255, g = 0, b = 0, a = 1 } }, -- ff660000
  { baseTag = "POWERBAR_PREDICTION_COLOR_FOCUS", color = { r = 102 / 255, g = 34 / 255, b = 0, a = 1 } }, -- ff662200
  { baseTag = "POWERBAR_PREDICTION_COLOR_ENERGY", color = { r = 115 / 255, g = 102 / 255, b = 0, a = 1 } }, -- ff736600
  { baseTag = "POWERBAR_PREDICTION_COLOR_RUNIC_POWER", color = { r = 0, g = 83 / 255, b = 102 / 255, a = 1 } }, -- ff005366
  { baseTag = "POWERBAR_PREDICTION_COLOR_LUNAR_POWER", color = { r = 15 / 255, g = 47 / 255, b = 103 / 255, a = 1 } }, -- ff0f2f67
  { baseTag = "POWERBAR_PREDICTION_COLOR_MAELSTROM", color = { r = 0, g = 51 / 255, b = 102 / 255, a = 1 } }, -- ff003366
  { baseTag = "POWERBAR_PREDICTION_COLOR_INSANITY", color = { r = 51 / 255, g = 0, b = 102 / 255, a = 1 } }, -- ff330066
  { baseTag = "POWERBAR_PREDICTION_COLOR_FURY", color = { r = 72 / 255, g = 2 / 255, b = 100 / 255, a = 1 } }, -- ff480264
  { baseTag = "POWERBAR_PREDICTION_COLOR_PAIN", color = { r = 102 / 255, g = 63 / 255, b = 0, a = 1 } }, -- ff663f00
  -- source: row W89 (confirmed) GlobalColor rows 363, 379, 108, 393, 394, 272 (ARGB in each comment); shared
  -- compactunitframe.lua reads them (the background colour at forever :709, tbc :705); no extract Lua defines them.
  { baseTag = "COMPACT_UNIT_FRAME_FRIENDLY_HEALTH_COLOR", color = { r = 43 / 255, g = 147 / 255, b = 5 / 255, a = 1 } }, -- ff2b9305
  { baseTag = "COMPACT_UNIT_FRAME_FRIENDLY_HEALTH_COLOR_BG", color = { r = 20 / 255, g = 20 / 255, b = 20 / 255, a = 1 } }, -- ff141414
  { baseTag = "NO_THREAT_COLOR", color = { r = 176 / 255, g = 176 / 255, b = 176 / 255, a = 1 } }, -- ffb0b0b0
  { baseTag = "GAINING_THREAT_COLOR", color = { r = 248 / 255, g = 181 / 255, b = 0, a = 1 } }, -- fff8b500
  { baseTag = "HIGH_THREAT_COLOR", color = { r = 1, g = 69 / 255, b = 11 / 255, a = 1 } }, -- ffff450b
  { baseTag = "PLAYER_NAMEPLATE_ALTERNATE_HEALTH_COLOR", color = { r = 0, g = 173 / 255, b = 240 / 255, a = 1 } }, -- ff00adf0
  -- source: row W91 (confirmed) GlobalColor rows 365-370 (ARGB in each comment); forever's AuraUtil builds its dispel type
  -- table from them at load (blizzard_framexmlutil/aurautil.lua:4-10); no extract Lua defines them.
  { baseTag = "DEBUFF_TYPE_MAGIC_COLOR", color = { r = 0, g = 129 / 255, b = 1, a = 1 } }, -- ff0081ff
  { baseTag = "DEBUFF_TYPE_POISON_COLOR", color = { r = 123 / 255, g = 199 / 255, b = 0, a = 1 } }, -- ff7bc700
  { baseTag = "DEBUFF_TYPE_CURSE_COLOR", color = { r = 159 / 255, g = 6 / 255, b = 228 / 255, a = 1 } }, -- ff9f06e4
  { baseTag = "DEBUFF_TYPE_BLEED_COLOR", color = { r = 184 / 255, g = 0, b = 15 / 255, a = 1 } }, -- ffb8000f
  { baseTag = "DEBUFF_TYPE_DISEASE_COLOR", color = { r = 241 / 255, g = 106 / 255, b = 9 / 255, a = 1 } }, -- fff16a09
  { baseTag = "DEBUFF_TYPE_NONE_COLOR", color = { r = 204 / 255, g = 0, b = 0, a = 1 } }, -- ffcc0000
  -- source: row W93 (confirmed) GlobalColor rows 12, 35, 50, 100-104, 121, 156, 415 (ARGB in each comment); Blizzard's
  -- XML names them in <Color color="..."/> (row X42); no extract Lua defines them.
  { baseTag = "DARKYELLOW_FONT_COLOR", color = { r = 1, g = 209 / 255, b = 0, a = 1 } }, -- ffffd100
  { baseTag = "BLACK_FONT_COLOR", color = { r = 0, g = 0, b = 0, a = 1 } }, -- ff000000
  { baseTag = "NEW_FEATURE_SHADOW_COLOR", color = { r = 82 / 255, g = 128 / 255, b = 1, a = 1 } }, -- ff5280ff
  { baseTag = "TRIVIAL_DIFFICULTY_COLOR", color = { r = 128 / 255, g = 128 / 255, b = 128 / 255, a = 1 } }, -- ff808080
  { baseTag = "EASY_DIFFICULTY_COLOR", color = { r = 64 / 255, g = 192 / 255, b = 64 / 255, a = 1 } }, -- ff40c040
  { baseTag = "FAIR_DIFFICULTY_COLOR", color = { r = 1, g = 1, b = 0, a = 1 } }, -- ffffff00
  { baseTag = "DIFFICULT_DIFFICULTY_COLOR", color = { r = 1, g = 128 / 255, b = 64 / 255, a = 1 } }, -- ffff8040
  { baseTag = "IMPOSSIBLE_DIFFICULTY_COLOR", color = { r = 1, g = 32 / 255, b = 32 / 255, a = 1 } }, -- ffff2020
  { baseTag = "ERROR_COLOR", color = { r = 1, g = 32 / 255, b = 32 / 255, a = 1 } }, -- ffff2020
  { baseTag = "DEFAULT_MATERIAL_TEXT_COLOR", color = { r = 46 / 255, g = 31 / 255, b = 15 / 255, a = 1 } }, -- ff2e1f0f
  { baseTag = "GAMEPAD_SMARTNAV_CURSOR_COLOR", color = { r = 1, g = 230 / 255, b = 0, a = 1 } }, -- ffffe600
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

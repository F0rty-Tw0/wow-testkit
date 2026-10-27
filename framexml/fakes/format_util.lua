-- Number, money and time formatters: BreakUpLargeNumbers, FormatLargeNumber, AbbreviateNumbers and
-- AbbreviateLargeNumbers, GetMoneyString, C_CurrencyInfo.GetCoinText and GetCoinTextureString, SecondsToTime and
-- GetTimePreciseSec. Kit-authored bodies over the behaviour row W70 records and the global strings in strings.lua.
local M = {}

local Core = require("framexml.fakes.core")

-- Localized: addon code may assign globals named ipairs, rawget or tostring.
local ipairs, rawget, tostring = ipairs, rawget, tostring
local floor, ceil = math.floor, math.ceil
local format, concat = string.format, table.concat

local API_GATE = { gate = "api" }
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local THOUSAND = 1000
local GROUP = 3
local COPPER_PER_SILVER = 100
local SILVER_PER_GOLD = 100
local COPPER_PER_GOLD = COPPER_PER_SILVER * SILVER_PER_GOLD
local DEFAULT_FONT_HEIGHT = 14
local DEFAULT_SEPARATOR = ", "
local SECONDS_PER_MIN = 60
local SECONDS_PER_HOUR = 60 * SECONDS_PER_MIN
local SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR
local DEFAULT_MAX_TERMS = 2
local SINGLE_TERM_THRESHOLD = 1.5
-- source: strings/enUS.lua FIRST_NUMBER_CAP_NO_SPACE .. FOURTH_NUMBER_CAP_NO_SPACE (row W70: the no-space form is assumed).
local NUMBER_CAPS = { "K", "M", "B", "T" }
-- source: row W70 (confirmed) the abbreviated time terms are HOURS_ABBR "%d |4Hr:Hr;" and its siblings and the delimiter
-- is TIME_UNIT_DELIMITER " "; resolving the plural forms here is assumed.
local TIME_UNITS = {
  { seconds = SECONDS_PER_DAY, short = { "Day", "Days" }, long = { "Day", "Days" } },
  { seconds = SECONDS_PER_HOUR, short = { "Hr", "Hr" }, long = { "Hour", "Hours" } },
  { seconds = SECONDS_PER_MIN, short = { "Min", "Min" }, long = { "Minute", "Minutes" } },
}
local SECONDS_UNIT = { short = { "Sec", "Sec" }, long = { "Second", "Seconds" } }
local ICONS = { gold = "UI-GoldIcon", silver = "UI-SilverIcon", copper = "UI-CopperIcon" }

-- source: row W70 (confirmed) FormatLargeNumber joins groups of three digits with LARGE_NUMBER_SEPERATOR. Read at call
-- time, as the client does, so an addon or a locale may change it.
local function formatLargeNumber(amount)
  local digits = tostring(amount)
  local separator = rawget(_G, "LARGE_NUMBER_SEPERATOR") or ","
  local head = #digits % GROUP
  local out = head > 0 and digits:sub(1, head) or ""
  for first = head + 1, #digits, GROUP do
    out = out .. (out == "" and "" or separator) .. digits:sub(first, first + GROUP - 1)
  end

  return out
end

-- source: row W70 (assumed: engine-side) the same grouping on the whole part.
local function breakUpLargeNumbers(number)
  return formatLargeNumber(floor(number))
end

-- source: row W70 (assumed: engine-side) under a thousand as is, then K, M, B and T with one decimal that a round value drops.
local function abbreviate(number)
  local value, cap = number, nil
  for _, letter in ipairs(NUMBER_CAPS) do
    if value < THOUSAND then
      break
    end
    value, cap = value / THOUSAND, letter
  end
  if not cap then
    return tostring(floor(number))
  end
  local text = format("%.1f", floor(value * 10) / 10):gsub("%.0$", "")

  return text .. cap
end

local function denominations(copper)
  local gold = floor(copper / COPPER_PER_GOLD)
  local silver = floor((copper - gold * COPPER_PER_GOLD) / COPPER_PER_SILVER)

  return gold, silver, copper % COPPER_PER_SILVER
end

local function icon(name, size)
  return format("|TInterface\\MoneyFrame\\%s:%d:%d:2:0|t", ICONS[name], size, size)
end

-- The gold amount above which checkGoldThreshold drops the copper is
-- Constants.MoneyFormattingConstants.GOLD_REWARD_THRESHOLD_TO_HIDE_COPPER (api/retail/MoneyConstants.lua); no threshold
-- applies in a world that lacks it.
local function copperHidden(gold)
  local constants = rawget(_G, "Constants")
  local formatting = constants and constants.MoneyFormattingConstants
  local threshold = formatting and formatting.GOLD_REWARD_THRESHOLD_TO_HIDE_COPPER

  return threshold ~= nil and gold > threshold
end

-- source: row W70 (confirmed) texture form 1|T...UI-GoldIcon:0:0:2:0|t 23|T...|t 45|T...|t. Empty denominations are left
-- out and a zero total reads as copper, or as gold with showZeroAsGold. The colour-blind form (1g 23s 45c) needs the
-- colourblindMode CVar, which arrives with the CVar fakes: not modelled.
local function getMoneyString(money, separateThousands, checkGoldThreshold, showZeroAsGold, color)
  local gold, silver, copper = denominations(money)
  local goldText = separateThousands and formatLargeNumber(gold) or tostring(gold)
  local out
  if showZeroAsGold and money == 0 then
    out = goldText .. icon("gold", 0)
  else
    local parts = {}
    parts[#parts + 1] = gold > 0 and goldText .. icon("gold", 0) or nil
    parts[#parts + 1] = silver > 0 and silver .. icon("silver", 0) or nil
    if (copper > 0 and not (checkGoldThreshold and copperHidden(gold))) or #parts == 0 then
      parts[#parts + 1] = copper .. icon("copper", 0)
    end
    out = concat(parts, " ")
  end

  return color and color:WrapTextInColorCode(out) or out
end

-- source: row W70 (confirmed) separates with ", " by default (GetCoinText is C_CurrencyInfo.GetCoinText in 12.x). The
-- words come from GOLD_AMOUNT, SILVER_AMOUNT and COPPER_AMOUNT; a zero denomination is left out (assumed).
local function getCoinText(amount, separator)
  local gold, silver, copper = denominations(amount)
  local parts = {}
  for _, entry in ipairs({ { gold, "GOLD_AMOUNT" }, { silver, "SILVER_AMOUNT" }, { copper, "COPPER_AMOUNT" } }) do
    if entry[1] > 0 then
      parts[#parts + 1] = format(rawget(_G, entry[2]) or "%d", entry[1])
    end
  end

  return concat(parts, separator or DEFAULT_SEPARATOR)
end

-- The icons sized by fontHeight (assumed: the api names that argument, default 14).
local function getCoinTextureString(amount, fontHeight)
  local size = fontHeight or DEFAULT_FONT_HEIGHT
  local gold, silver, copper = denominations(amount)
  local parts = {}
  for _, entry in ipairs({ { gold, "gold" }, { silver, "silver" }, { copper, "copper" } }) do
    if entry[1] > 0 then
      parts[#parts + 1] = entry[1] .. icon(entry[2], size)
    end
  end

  return concat(parts, " ")
end

local function term(unit, count, notAbbreviated)
  local names = notAbbreviated and unit.long or unit.short

  return format("%d %s", count, count == 1 and names[1] or names[2])
end

-- source: row W70 (confirmed: structure, 3725 -> "1 Hr 2 Min"; assumed: plural resolution) at most maxCount terms of
-- days, hours, minutes and seconds; a single term alone needs 1.5 of its unit to show. roundUp rounds the last term up.
local function secondsToTime(seconds, noSeconds, notAbbreviated, maxCount, roundUp)
  seconds = roundUp and ceil(seconds) or floor(seconds)
  maxCount = maxCount or DEFAULT_MAX_TERMS
  local threshold = maxCount > 1 and 1 or SINGLE_TERM_THRESHOLD
  local terms = {}
  for _, unit in ipairs(TIME_UNITS) do
    if #terms < maxCount and seconds >= unit.seconds * threshold then
      local rounding = (#terms + 1 == maxCount and roundUp) and ceil or floor
      terms[#terms + 1] = term(unit, rounding(seconds / unit.seconds), notAbbreviated)
      seconds = seconds % unit.seconds
    end
  end
  if #terms < maxCount and seconds > 0 and not noSeconds then
    terms[#terms + 1] = term(SECONDS_UNIT, seconds, notAbbreviated)
  end

  return concat(terms, " ")
end

function M.install(w)
  w:install("FormatLargeNumber", formatLargeNumber, KETHO_GATE)
  w:install("BreakUpLargeNumbers", breakUpLargeNumbers, API_GATE)
  w:install("AbbreviateNumbers", abbreviate, API_GATE)
  w:install("AbbreviateLargeNumbers", abbreviate, API_GATE)
  w:install("GetMoneyString", getMoneyString, KETHO_GATE)
  w:install("C_CurrencyInfo.GetCoinText", getCoinText, API_GATE)
  w:install("C_CurrencyInfo.GetCoinTextureString", getCoinTextureString, API_GATE)
  w:install("SecondsToTime", secondsToTime, KETHO_GATE)
  -- Assumed (no flavor's api or FrameXML list names it): the world clock, so a test that advances it moves it.
  w:install("GetTimePreciseSec", function()
    return w.now
  end, Core.GATE)
end

return M

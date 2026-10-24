-- A resolve that raises or yields: ui/layout.lua leaves no mark behind and passes the error on untouched.
local A = require("assert")
local HL = require("tests.helpers.layout")
local Measure = require("ui.measure")

local SCREEN = { width = 1000, height = 800 }
local FONT = "Fonts\\FRIZQT__.TTF"

-- A FontString at the screen corner whose text width comes from glyph, so glyph runs inside its resolve.
local function measuredText(w, glyph)
  Measure.useGlyphs(w, { [FONT] = { width = glyph } })
  local fs = _G.CreateFrame("Frame"):CreateFontString()
  fs:SetFont(FONT, 10)
  fs:SetText("abc")
  fs:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 10, 10)
  return fs
end

local function test_a_resolve_error_comes_back_with_its_message_and_traceback()
  HL.withLayout(SCREEN, function()
    local f = _G.CreateFrame("Frame")
    f:SetSize(10, 10)
    f:SetPoint("TOP", _G.UIParent, "TOP", "abc", 0) -- a string offset: the arithmetic raises while resolving
    local ok, trace = xpcall(function()
      return f:GetLeft()
    end, debug.traceback)
    A.eq(ok, false)
    A.truthy(trace:find("layout%.lua:%d+: attempt to perform arithmetic"), trace) -- the original file:line
    A.truthy(trace:find("'compute'", 1, true), trace) -- the frames of the failed resolve are still on the stack
  end)
end

local function test_a_table_error_from_a_nested_resolve_is_the_same_object()
  HL.withLayout(SCREEN, function(w)
    local errObj = { code = 42 }
    local inner = measuredText(w, function()
      error(errObj)
    end)
    local outer = _G.CreateFrame("Frame")
    outer:SetSize(10, 10)
    outer:SetPoint("BOTTOMLEFT", inner, "TOPRIGHT") -- outer resolves inner inside its own resolve
    for _ = 1, 2 do -- twice: the first failure leaves no mark that turns the second into a silent nothing
      local ok, err = pcall(outer.GetLeft, outer)
      A.eq(ok, false)
      A.eq(err, errObj)
    end
  end)
end

local function test_a_resolve_can_yield_and_resume()
  HL.withLayout(SCREEN, function(w)
    local fs = measuredText(w, function(size, _, text)
      coroutine.yield("paused")
      return #text * size
    end)
    local co = coroutine.create(function()
      return fs:GetWidth()
    end)
    local ok, first = coroutine.resume(co)
    A.eq(first, "paused", ok and "" or tostring(first)) -- not "attempt to yield across metamethod/C-call boundary"
    ok, first = coroutine.resume(co)
    A.truthy(ok, tostring(first))
    A.eq(first, 30)
  end)
end

return function()
  test_a_resolve_error_comes_back_with_its_message_and_traceback()
  test_a_table_error_from_a_nested_resolve_is_the_same_object()
  test_a_resolve_can_yield_and_resume()
end

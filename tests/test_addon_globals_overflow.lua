-- An addon _G __index handler that reads its own global again overflows the C stack; the message names the handler's
-- line or no line, never a kit file (docs/client-sources.md L2 known gap).
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.world")
local fs = require("fs")

local SELF_READING = "setmetatable(_G, { __index = function(_, key) return _G[key] end })\nlocal _ = Missing\n"

local function overflowMessage()
  local root = Tmp.dir("addon") .. "/Overflow"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Overflow.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", SELF_READING)
  local message
  H.withWorld("retail", function(w)
    Addon.load(w, { name = "Overflow", root = root })
    message = #w.errors == 1 and w.errors[1].message
  end)
  return message
end

-- Each kit cycle holds two C calls, one at the addon's line and one in pcall, so which one hits the limit flips
-- with every C call already on the stack; one extra pcall level shows both forms.
local function test_self_reading_globals_handler_overflow_names_the_addon_line_or_none()
  local messages = { overflowMessage(), select(2, pcall(overflowMessage)) }
  table.sort(messages)
  A.same(messages, { "C stack overflow", "addon:Overflow/Core.lua:1: C stack overflow" })
end

return function()
  test_self_reading_globals_handler_overflow_names_the_addon_line_or_none()
end

-- The phase demo data (windows_demo.lua, Task 12.8): every entry opens its window with no extract, and it carries no
-- Blizzard string (a name is kit-authored or absent, so the client's data names the items).
local A = require("assert")
local BlizzardWindows = require("blizzard_windows")
local Demo = require("windows_demo")
local W = require("tests.helpers.windows")

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function test_every_demo_window_opens_without_errors()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    W.scenario(flavor, {}, function(s)
      local opened = {}
      for _, window in ipairs(sortedKeys(Demo)) do
        if BlizzardWindows.spec(s.w, window) then
          s:openWindow(window, Demo[window])
          s:closeWindow(window)
          opened[#opened + 1] = window
        end
      end
      A.eq(#s.w.errors, 0, flavor .. ": " .. tostring(s.w.errors[1] and s.w.errors[1].message))
      local expected = flavor == "vanilla" and 5 or 6 -- vanilla has no transmog window, as tbc
      A.eq(#opened, expected, flavor)
    end)
  end
end

-- Every value under a key `name`, at any depth, in out.
local function names(t, out)
  for key, value in pairs(t) do
    if key == "name" then
      out[#out + 1] = value
    elseif type(value) == "table" then
      names(value, out)
    end
  end
  return out
end

local function test_demo_data_has_no_blizzard_strings()
  for _, name in ipairs(names(Demo, {})) do
    A.truthy(type(name) == "string" and name:sub(1, 4) == "Kit ", "demo name " .. tostring(name))
  end
end

return function()
  test_every_demo_window_opens_without_errors()
  test_demo_data_has_no_blizzard_strings()
end

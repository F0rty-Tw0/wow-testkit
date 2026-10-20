-- DropdownButton: generator changes on an open menu, the template's OnShow, and the mixin methods past the basics.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function noop() end

local function newDropdown(generator)
  local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent, "WowStyle1DropdownTemplate")
  if generator then
    dd:SetupMenu(generator)
  end
  return dd
end

local function oneButton(text)
  return function(_, root)
    root:CreateButton(text, noop)
  end
end

local function texts(level)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry.text
  end
  return out
end

local function test_setup_menu_on_an_open_menu_shows_the_new_generators_entries() -- (D5)
  withFrameXML("retail", function(w)
    local dd = newDropdown(oneButton("Old"))
    dd:OpenMenu()
    dd:SetupMenu(oneButton("New"))
    A.eq(dd:IsMenuOpen(), true)
    A.same(texts(w.menus[1]), { "New" })
    dd:CloseMenu()
    dd:OpenMenu()
    A.same(texts(w.menus[1]), { "New" })
  end)
end

return function()
  test_setup_menu_on_an_open_menu_shows_the_new_generators_entries()
end

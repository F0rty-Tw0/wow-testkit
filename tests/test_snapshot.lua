-- Snapshot: GameTooltip and frame trees as stable text (colors as hex runs, no paths or line numbers).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Snapshot = require("snapshot")

local function lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

local function withTooltip(fn)
  HF.withFrameXML("retail", function()
    fn(_G.GameTooltip)
  end)
end

local function test_tooltip_color_escape_splits_the_line_into_runs()
  withTooltip(function(tip)
    tip:AddLine("|cffff0000Red|r text", 1, 1, 1)
    A.eq(lines(Snapshot.tooltip(tip))[1], "L: [ff0000]Red[ffffff] text")
  end)
end

local function test_tooltip_double_line_adds_the_right_runs()
  withTooltip(function(tip)
    tip:AddDoubleLine("a", "b", 1, 0, 0, 0, 1, 0)
    A.eq(lines(Snapshot.tooltip(tip))[1], "L: [ff0000]a | R: [00ff00]b")
  end)
end

local function test_tooltip_texture_escape_becomes_a_tex_token()
  withTooltip(function(tip)
    tip:AddLine("|TInterface\\Icons\\Foo:14:14|t Hi", 1, 1, 1)
    A.eq(lines(Snapshot.tooltip(tip))[1], "L: [ffffff][tex:Interface\\Icons\\Foo] Hi")
  end)
end

local function test_tooltip_ends_with_the_border_color()
  withTooltip(function(tip)
    tip:AddLine("x", 1, 1, 1)
    tip.NineSlice:SetBorderColor(1, 0.5, 0)
    local out = lines(Snapshot.tooltip(tip))
    A.eq(out[#out], "border=ff8000")
  end)
end

local function test_frame_lists_size_font_strings_and_textures()
  HF.withFrameXML("retail", function()
    local root = _G.CreateFrame("Frame", "SnapRoot", _G.UIParent)
    root:SetSize(100.4, 20)
    root:CreateFontString():SetText("Hi")
    root:CreateTexture():SetTexture("Interface\\X")
    _G.CreateFrame("Frame", nil, root)
    A.textEq(Snapshot.frame(root), 'Frame "SnapRoot" 100x20\n  FontString "[ffffff]Hi"\n  Texture Interface\\X\n  Frame "-" 0x0')
  end)
end

local function test_frame_omits_a_hidden_child_subtree()
  HF.withFrameXML("retail", function()
    local root = _G.CreateFrame("Frame", "SnapRoot", _G.UIParent)
    local hidden = _G.CreateFrame("Frame", "SnapHidden", root)
    _G.CreateFrame("Frame", "SnapInner", hidden)
    hidden:Hide()
    local text = Snapshot.frame(root)
    A.eq(text:find("SnapHidden", 1, true), nil)
    A.eq(text:find("SnapInner", 1, true), nil)
  end)
end

local function menu(levels)
  return { kind = "menu", levels = levels }
end

local function item(kind, text, extra)
  local e = { kind = kind, text = text, enabled = true, checked = false, hasSubmenu = false }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end

local function test_menu_renders_one_line_per_entry_by_kind()
  local value = menu({
    {
      entries = {
        item("checkbox", "Show", { checked = true }),
        item("checkbox", "Hide"),
        item("radio", "A", { checked = true }),
        item("radio", "B"),
        item("button", "Open"),
        item("title", "Head"),
        item("divider"),
      },
    },
  })
  A.textEq(Snapshot.menu(value), "[x] [ffffff]Show\n[ ] [ffffff]Hide\n(o) [ffffff]A\n( ) [ffffff]B\n[ffffff]Open\n== [ffffff]Head ==\n---")
end

local function test_menu_marks_submenu_and_disabled_entries()
  local value = menu({
    {
      entries = {
        item("button", "More", { hasSubmenu = true, enabled = false }),
        item("checkbox", "Both", { hasSubmenu = true, checked = true }),
      },
    },
  })
  A.textEq(Snapshot.menu(value), "> [ffffff]More (disabled)\n[x] > [ffffff]Both")
end

local function test_menu_nests_an_open_submenu_under_its_entry()
  local value = menu({
    { entries = { item("button", "A"), item("button", "More", { hasSubmenu = true }), item("button", "C") } },
    { parentIndex = 2, entries = { item("button", "Nested") } },
  })
  A.textEq(Snapshot.menu(value), "[ffffff]A\n> [ffffff]More\n  [ffffff]Nested\n[ffffff]C")
end

local function test_menu_closed_submenu_shows_only_its_own_line()
  local value = menu({ { entries = { item("button", "More", { hasSubmenu = true }) } } })
  A.textEq(Snapshot.menu(value), "> [ffffff]More")
end

local function test_menu_keeps_color_as_runs()
  local value = menu({ { entries = { item("button", "|cffff0000Red|r tail") } } })
  A.textEq(Snapshot.menu(value), "[ff0000]Red[ffffff] tail")
end

return function()
  test_tooltip_color_escape_splits_the_line_into_runs()
  test_tooltip_double_line_adds_the_right_runs()
  test_tooltip_texture_escape_becomes_a_tex_token()
  test_tooltip_ends_with_the_border_color()
  test_frame_lists_size_font_strings_and_textures()
  test_frame_omits_a_hidden_child_subtree()
  test_menu_renders_one_line_per_entry_by_kind()
  test_menu_marks_submenu_and_disabled_entries()
  test_menu_nests_an_open_submenu_under_its_entry()
  test_menu_closed_submenu_shows_only_its_own_line()
  test_menu_keeps_color_as_runs()
end

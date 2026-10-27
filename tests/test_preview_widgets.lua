-- The WidgetDemo fixture (one of each widget kind, drawn with colour textures) through Preview.run, the path `tk preview`
-- takes, at 900x600 (UI scale 1). The demo's root is 600x400 centred, so its top-left is (150, 100); y = top-left origin.
local A = require("assert")
local Json = require("json")
local P = require("tests.helpers.preview")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local DEMO = TEST_DIR .. "/fixtures/addons/WidgetDemo"
local SCREEN = { width = 900, height = 600 }
local LINES = 10
local LINE_HEIGHT = 20

local function demoSnapshot()
  local snapshot
  P.withExec(nil, function()
    local out = Tmp.dir("previewwidgets")
    local code = P.run({ addonDir = DEMO, out = out, size = SCREEN })
    A.eq(code, 0)
    snapshot = Json.decode(assert(fs.readFile(out .. "/snapshot.json")))
  end)

  return snapshot
end

local function named(snapshot, name)
  for _, item in ipairs(snapshot.items) do
    if item.name == name then
      return item
    end
  end
  error("the snapshot has no item named " .. name)
end

local function childrenOf(snapshot, parent, kind)
  local found = {}
  for _, item in ipairs(snapshot.items) do
    if item.parent == parent.id and item.kind == kind then
      found[#found + 1] = item
    end
  end

  return found
end

local function test_the_button_draws_its_normal_texture_over_the_whole_button()
  local snapshot = demoSnapshot()
  local button = named(snapshot, "WidgetDemoButton")
  local blue = {}
  for _, texture in ipairs(childrenOf(snapshot, button, "texture")) do
    blue[#blue + 1] = { texture.color, texture.rect }
  end
  local rect = { x = 170, y = 120, width = 120, height = 30 }
  A.eq(button.widget.type, "Button")
  A.same(button.rect, rect)
  A.same(blue, { { { 0.2, 0.4, 0.9, 1 }, rect } })
end

local function test_the_status_bar_exports_the_data_its_fill_is_drawn_from()
  local widget = named(demoSnapshot(), "WidgetDemoBar").widget
  A.same(widget.color, { 0, 1, 0, 1 })
  A.same(widget.texture, { color = { 1, 1, 1, 1 } })
  A.same({ widget.value, widget.min, widget.max }, { 40, 0, 100 })
end

local function test_the_scroll_child_and_its_lines_are_laid_out_and_clipped()
  local snapshot = demoSnapshot()
  local scroll = named(snapshot, "WidgetDemoScroll")
  local content = named(snapshot, "WidgetDemoContent")
  A.eq(scroll.widget.child, content.id)
  A.same({ scroll.widget.hRange, scroll.widget.vRange }, { 0, 140 })
  A.same(content.rect, { x = 410, y = 170, width = 160, height = 200 })
  local lines = childrenOf(snapshot, content, "fontstring")
  A.eq(#lines, LINES)
  for line, item in ipairs(lines) do
    A.same({ item.text, item.rect.x, item.rect.y, item.clip }, { "Line " .. line, 414, 172 + (line - 1) * LINE_HEIGHT, scroll.rect })
  end
end

return function()
  test_the_button_draws_its_normal_texture_over_the_whole_button()
  test_the_status_bar_exports_the_data_its_fill_is_drawn_from()
  test_the_scroll_child_and_its_lines_are_laid_out_and_clipped()
end

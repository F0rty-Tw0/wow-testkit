-- Widget inheritance. Method names and ancestors come from Ketho's WidgetAPI (globals.widgets: per type
-- `inherits` + `methods`); this file adds only the type -> Blizzard doc systems map used for signatures.
local M = {}

local REGION_CHAIN = {
  "SimpleRegionAPI",
  "SimpleScriptRegionResizingAPI",
  "SimpleScriptRegionAPI",
  "SimpleObjectAPI",
  "SimpleFrameScriptObjectAPI",
}
local FRAME_CHAIN = {
  "SimpleFrameAPI",
  "SimpleScriptRegionResizingAPI",
  "SimpleRegionAPI",
  "SimpleScriptRegionAPI",
  "SimpleObjectAPI",
  "SimpleFrameScriptObjectAPI",
}

-- Ketho lists Region inheriting itself; in the client Region inherits ScriptRegion.
local SELF_INHERIT_FIX = { Region = "ScriptRegion" }

local function chain(own, base)
  local out = {}
  for _, name in ipairs(own) do
    out[#out + 1] = name
  end
  for _, name in ipairs(base) do
    out[#out + 1] = name
  end
  return out
end

local DOC_SYSTEMS = {
  Frame = FRAME_CHAIN,
  Button = chain({ "SimpleButtonAPI" }, FRAME_CHAIN),
  CheckButton = chain({ "SimpleCheckboxAPI", "SimpleButtonAPI" }, FRAME_CHAIN),
  EditBox = chain({ "SimpleEditBoxAPI" }, FRAME_CHAIN),
  Slider = chain({ "SimpleSliderAPI" }, FRAME_CHAIN),
  StatusBar = chain({ "SimpleStatusBarAPI" }, FRAME_CHAIN),
  ScrollFrame = chain({ "SimpleScrollFrameAPI" }, FRAME_CHAIN),
  GameTooltip = chain({ "FrameAPITooltip" }, FRAME_CHAIN),
  Minimap = chain({ "MinimapFrameAPI" }, FRAME_CHAIN),
  Texture = chain({ "SimpleTextureAPI", "SimpleTextureBaseAPI" }, REGION_CHAIN),
  FontString = chain({ "SimpleFontStringAPI" }, REGION_CHAIN),
  Font = { "SimpleFontAPI", "SimpleFrameScriptObjectAPI" },
  AnimationGroup = { "SimpleAnimGroupAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" },
}

local EMPTY = {}

-- Ordered doc-system names for a widget type ({} when unmapped). Callers skip names a flavor's manifest lacks.
function M.docSystemsFor(typeName)
  return DOC_SYSTEMS[typeName] or EMPTY
end

local function visit(widgetTypes, typeName, out, seen)
  if seen[typeName] or not widgetTypes[typeName] then
    return
  end
  seen[typeName] = true
  out[#out + 1] = typeName
  for _, parent in ipairs(widgetTypes[typeName].inherits or EMPTY) do
    if parent == typeName then
      parent = SELF_INHERIT_FIX[typeName] or parent
    end
    visit(widgetTypes, parent, out, seen)
  end
end

-- typeName first, then its Ketho ancestors depth-first; each type once. {} for an unknown type.
function M.ancestors(widgetTypes, typeName)
  local out = {}
  visit(widgetTypes, typeName, out, {})
  return out
end

-- Set of every method name typeName has, own and inherited.
function M.methodNames(widgetTypes, typeName)
  local names = {}
  for _, ancestor in ipairs(M.ancestors(widgetTypes, typeName)) do
    for _, name in ipairs(widgetTypes[ancestor].methods or EMPTY) do
      names[name] = true
    end
  end
  return names
end

return M

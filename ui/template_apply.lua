-- Applies one ui/templates.lua entry to a frame CreateFrame just made: parentKey children, size, protection, mixins
-- and scripts. Widget creation goes through w.ui.create (ui/widgets.lua).
local M = {}

local AddonEnv = require("addon_env")
local Layout = require("ui.layout")
local Templates = require("ui.templates")
local WorldApi = require("world_api")

-- A template child whose type the flavor's Ketho WidgetAPI lacks is created as a plain frame.
local FALLBACK_CHILD_TYPE = "Frame"

-- Copies a mixin table's fields onto frame, like the client's Mixin(frame, mixin) (framexml/fakes/mixin.lua).
function M.copyMixin(frame, mixin)
  for key, value in pairs(mixin) do
    frame[key] = value
  end
end

-- Adds name to st.mixins, the mixins applied to the frame, unless a template or the frame's own list already brought it.
function M.recordMixin(st, name)
  st.mixins = st.mixins or {}
  for _, known in ipairs(st.mixins) do
    if known == name then
      return
    end
  end
  st.mixins[#st.mixins + 1] = name
end

-- The widget a template child is: a group comes from the frame's CreateAnimationGroup, anything else from w.ui.create.
local function makeChild(w, frame, child)
  if child.type == "AnimationGroup" then
    return frame:CreateAnimationGroup()
  end
  local childType = w.globals.widgets[child.type] and child.type or FALLBACK_CHILD_TYPE

  return w.ui.create(childType, nil, frame)
end

-- Sets up one child after it is stored under its key: the frame's setter that adopts it (adopt names the method,
-- buttonText is SetFontString), its anchor to the frame (anchor = { point, relativePoint, x, y }), its own size, and its
-- own template (a child that is itself a template element).
local function setUpChild(w, frame, obj, child)
  if child.buttonText then
    frame:SetFontString(obj)
  end
  if child.anchor then
    obj:SetPoint(child.anchor[1], frame, child.anchor[2], child.anchor[3], child.anchor[4])
  elseif child.buttonText then
    -- assumed: the client centres a <ButtonText> that has no anchors; the kit fills the button, as SetText does
    obj:SetAllPoints(frame)
  end
  if child.adopt then
    frame[child.adopt](frame, obj)
  end
  if child.size then
    obj:SetSize(child.size[1], child.size[2])
  end
  if child.template then
    M.applyList(w, obj, child.template)
  end
end

-- Applies entry after the entries its `inherits` names (the ones the kit has: the others are already flattened into
-- the entry), so a derived size, orientation or script wins over the inherited one.
function M.apply(w, frame, st, entry)
  for _, parent in ipairs(entry.inherits) do
    local base = Templates.TEMPLATES[parent]
    if base then
      M.apply(w, frame, st, base)
    end
  end
  for _, child in ipairs(entry.children) do
    local obj = makeChild(w, frame, child)
    frame[child.key] = obj
    setUpChild(w, frame, obj, child)
  end
  if entry.orientation then
    frame:SetOrientation(entry.orientation)
  end
  if entry.size then
    st.width, st.height = entry.size[1], entry.size[2]
    Layout.invalidate(w, frame)
  end
  st.protected = st.protected or entry.protected
  for _, name in ipairs(entry.mixins) do
    M.recordMixin(st, name)
    local mixin = AddonEnv.global(w, name, true)
    if type(mixin) == "table" then
      M.copyMixin(frame, mixin)
    end
  end
  -- A template script is the frame's own handler: SetScript replaces it, HookScript runs after it.
  -- A script given as a function is the kit's own (fn(w, self, ...)); a string names a method of the frame.
  for scriptName, method in pairs(entry.scripts or {}) do
    w:setScript(frame, scriptName, function(self, ...)
      if type(method) == "function" then
        return method(w, self, ...)
      end
      self[method](self, ...)
    end)
  end
  -- An XML function="" script is that global function itself; set only when the world defines it.
  for scriptName, name in pairs(entry.functions or {}) do
    local fn = AddonEnv.global(w, name, true)
    if type(fn) == "function" then
      w:setScript(frame, scriptName, fn)
    end
  end
  -- entry.methods = { Name = fn(w, self, ...) } become methods of the frame.
  for name, fn in pairs(entry.methods or {}) do
    frame[name] = function(self, ...)
      return fn(w, self, ...)
    end
  end
end

-- Applies a comma- or space-separated template list in order. A name registered by an XML virtual element
-- (w.ui.virtuals) wins over the kit's ui/templates.lua entry; an unknown one adds nothing and is counted in
-- w.unscripted["template:<Name>"].
-- source: wiki XML/LayoutFrame, `inherits` "Inherits a comma-separated list of XML virtual templates"; row X4 (each
-- applied before the element's own content: assumed)
function M.applyList(w, frame, templates)
  if type(templates) ~= "string" then
    return
  end
  local st = w.ui.state[frame]
  st.mixins = st.mixins or {}
  for name in templates:gmatch("[^,%s]+") do
    local virtual, entry = w.ui.virtuals[name], Templates.TEMPLATES[name]
    if virtual then
      virtual.apply(w, frame, st)
    elseif entry and (not entry.flavors or entry.flavors[w.flavor]) then
      M.apply(w, frame, st, entry)
    else
      WorldApi.markUnscripted(w, "template:" .. name)
    end
  end
end

return M

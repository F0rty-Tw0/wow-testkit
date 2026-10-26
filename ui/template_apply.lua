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

function M.apply(w, frame, st, entry)
  for _, child in ipairs(entry.children) do
    local childType = w.globals.widgets[child.type] and child.type or FALLBACK_CHILD_TYPE
    frame[child.key] = w.ui.create(childType, nil, frame)
    if child.buttonText then
      frame:SetFontString(frame[child.key])
    end
  end
  if entry.size then
    st.width, st.height = entry.size[1], entry.size[2]
    Layout.invalidate(w, frame)
  end
  st.protected = st.protected or entry.protected
  for _, name in ipairs(entry.mixins) do
    st.mixins[#st.mixins + 1] = name
    local mixin = AddonEnv.global(w, name, true)
    if type(mixin) == "table" then
      M.copyMixin(frame, mixin)
    end
  end
  -- A template script is the frame's own handler: SetScript replaces it, HookScript runs after it.
  for scriptName, method in pairs(entry.scripts or {}) do
    w:setScript(frame, scriptName, function(self)
      self[method](self)
    end)
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
    elseif entry then
      M.apply(w, frame, st, entry)
    else
      WorldApi.markUnscripted(w, "template:" .. name)
    end
  end
end

return M

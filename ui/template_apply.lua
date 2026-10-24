-- Applies one ui/templates.lua entry to a frame CreateFrame just made: parentKey children, size, protection, mixins
-- and scripts. Widget creation goes through w.ui.create (ui/widgets.lua).
local M = {}

local Layout = require("ui.layout")

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
  end
  if entry.size then
    st.width, st.height = entry.size[1], entry.size[2]
    Layout.invalidate(w, frame)
  end
  st.protected = st.protected or entry.protected
  for _, name in ipairs(entry.mixins) do
    st.mixins[#st.mixins + 1] = name
    local mixin = rawget(_G, name)
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

return M

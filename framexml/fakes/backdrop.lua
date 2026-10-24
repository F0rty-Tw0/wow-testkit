-- BackdropTemplateMixin: the SetBackdrop family a BackdropTemplate frame gets (ui/templates.lua copies the global onto
-- the frame). Minimal on purpose: it stores st.backdrop = { info, color, borderColor } for the render snapshot;
-- Task 6.7 owns the full Blizzard semantics.
local M = {}

local Core = require("framexml.fakes.core")

local unpack = unpack

local COLOR_FIELDS = 4
local OPAQUE = 1

local function white()
  return { 1, 1, 1, OPAQUE }
end

local function color(r, g, b, a)
  return { r, g, b, a or OPAQUE }
end

-- The st.backdrop of obj, nil without a backdrop.
local function backdropOf(w, obj)
  return w.ui.state[obj].backdrop
end

-- source: row V13 (confirmed), Blizzard_SharedXML/Backdrop.lua:330-331 in ApplyBackdrop, called by SetBackdrop (:346-347):
-- `self:SetBackdropColor(1, 1, 1, 1);` and `self:SetBackdropBorderColor(1, 1, 1, 1);`. SetBackdrop(nil) clears it.
local function newMixin(w)
  local mixin = {}

  function mixin.SetBackdrop(self, info)
    w.ui.state[self].backdrop = info and { info = info, color = white(), borderColor = white() } or nil
  end

  function mixin.GetBackdrop(self)
    local backdrop = backdropOf(w, self)
    return backdrop and backdrop.info
  end

  -- source: row V13 (confirmed) Backdrop.lua:398-400, :407-410, :417-419, :430-433: without a backdrop the setters do
  -- nothing and the getters return nothing; `a or 1` for the alpha (:412, :437).
  function mixin.SetBackdropColor(self, r, g, b, a)
    local backdrop = backdropOf(w, self)
    if backdrop then
      backdrop.color = color(r, g, b, a)
    end
  end

  function mixin.GetBackdropColor(self)
    local backdrop = backdropOf(w, self)
    if backdrop then
      return unpack(backdrop.color, 1, COLOR_FIELDS)
    end
  end

  function mixin.SetBackdropBorderColor(self, r, g, b, a)
    local backdrop = backdropOf(w, self)
    if backdrop then
      backdrop.borderColor = color(r, g, b, a)
    end
  end

  function mixin.GetBackdropBorderColor(self)
    local backdrop = backdropOf(w, self)
    if backdrop then
      return unpack(backdrop.borderColor, 1, COLOR_FIELDS)
    end
  end

  return mixin
end

function M.install(w)
  w:install("BackdropTemplateMixin", newMixin(w), Core.GATE)
end

return M

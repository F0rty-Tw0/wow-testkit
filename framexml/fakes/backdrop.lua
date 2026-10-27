-- BackdropTemplateMixin: the backdrop methods a BackdropTemplate frame gets (ui/templates.lua copies the global onto the
-- frame and runs OnBackdropLoaded as its OnLoad). The semantics are Blizzard_SharedXML/Backdrop.lua's, minus the nine
-- slice regions: the state is st.backdrop = { info, color, borderColor } for the render snapshot, and the frame's own
-- backdropInfo field holds the info table as the client's does.
local M = {}

local Core = require("framexml.fakes.core")

local unpack = unpack

local COLOR_FIELDS = 4
local OPAQUE = 1
local MISSING_INFO = "attempt to index field 'backdropInfo' (a nil value)"
-- source: row W47 (confirmed) Backdrop.lua:157 (defaultEdgeSize, "the old default") and :195-201 (GetEdgeSize).
local DEFAULT_EDGE_SIZE = 39
local INSET_SIDES = { "left", "right", "top", "bottom" }

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

-- source: row W47 (confirmed) Backdrop.lua:159-187 (OnBackdropLoaded): a colour field is read with GetRGB, white when
-- absent, the alpha field defaults to 1. A plain { r, g, b } table is read by its fields (assumed: the kit takes it where
-- the client's field would be a ColorMixin).
local function channels(field, alpha)
  local r, g, b = 1, 1, 1
  if type(field) == "table" and field.GetRGB then
    r, g, b = field:GetRGB()
  elseif type(field) == "table" then
    r, g, b = field.r, field.g, field.b
  end

  return r, g, b, alpha or OPAQUE
end

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = copyTable(item)
  end

  return copy
end

-- source: row W47 (confirmed) Backdrop.lua:354-396 (GetBackdrop): a copy of backdropInfo with bgFile and edgeFile "", tile
-- false, tileSize 0, tileEdge true, edgeSize from GetEdgeSize and every inset 0 filled in where absent.
local function withDefaults(self, info)
  local copy = copyTable(info)
  copy.bgFile = copy.bgFile or ""
  copy.edgeFile = copy.edgeFile or ""
  copy.tile = copy.tile or false
  copy.tileSize = copy.tileSize or 0
  if copy.tileEdge == nil then
    copy.tileEdge = true
  end
  copy.edgeSize = copy.edgeSize or self:GetEdgeSize()
  copy.insets = copy.insets or {}
  for _, side in ipairs(INSET_SIDES) do
    copy.insets[side] = copy.insets[side] or 0
  end

  return copy
end

local function hasPieces(info)
  return info.edgeFile or info.bgFile
end

-- The method set of one world. Methods run with self = the frame the template was applied to.
local function newMixin(w)
  local mixin = {}

  -- source: row W47 (confirmed) Backdrop.lua:301-332 (ApplyBackdrop): it uses the frame's backdropInfo field (an absent one
  -- is an error, :303), does not re-read the colour fields, and ends by setting both colours to 1, 1, 1, 1 (:330-331).
  function mixin.ApplyBackdrop(self)
    local info = self.backdropInfo
    if not info then
      error(MISSING_INFO, 2)
    end
    w.ui.state[self].backdrop = { info = info, color = white(), borderColor = white() }
  end

  function mixin.HasBackdropInfo(self, info)
    return self.backdropInfo == info
  end

  -- source: row W47 (confirmed) Backdrop.lua:289-300 (ClearBackdrop): with no backdropInfo it does nothing.
  function mixin.ClearBackdrop(self)
    if self.backdropInfo then
      w.ui.state[self].backdrop = nil
      self.backdropInfo = nil
    end
  end

  -- source: row W47 (confirmed) Backdrop.lua:336-352 (SetBackdrop): the table already set is a no-op (the colours stay);
  -- a table with neither bgFile nor edgeFile clears; nil clears; any other table is applied.
  function mixin.SetBackdrop(self, info)
    if not info then
      return self:ClearBackdrop()
    end
    if self:HasBackdropInfo(info) then
      return
    end
    if not hasPieces(info) then
      return self:ClearBackdrop()
    end
    self.backdropInfo = info
    self:ApplyBackdrop()
  end

  -- source: row W47 (confirmed) Backdrop.lua:159-187 (OnBackdropLoaded): nothing without backdropInfo; a table with
  -- neither file is dropped; otherwise ApplyBackdrop, then the colour fields and the border blend mode.
  function mixin.OnBackdropLoaded(self)
    local info = self.backdropInfo
    if not info then
      return
    end
    if not hasPieces(info) then
      self.backdropInfo = nil
      return
    end
    self:ApplyBackdrop()
    self:SetBackdropColor(channels(self.backdropColor, self.backdropColorAlpha))
    self:SetBackdropBorderColor(channels(self.backdropBorderColor, self.backdropBorderColorAlpha))
    if self.backdropBorderBlendMode then
      self:SetBorderBlendMode(self.backdropBorderBlendMode)
    end
  end

  -- source: Backdrop.lua:273-283 (SetBorderBlendMode). The border blend mode changes no exported value (the border pieces are not snapshot regions), so it is accepted and
  -- not stored.
  function mixin.SetBorderBlendMode() end

  function mixin.GetEdgeSize(self)
    local size = self.backdropInfo.edgeSize

    return size and size > 0 and size or DEFAULT_EDGE_SIZE
  end

  function mixin.GetBackdrop(self)
    local info = self.backdropInfo

    return info and withDefaults(self, info) or nil
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

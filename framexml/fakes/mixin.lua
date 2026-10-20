-- Mixin and CreateFromMixins (C APIs in every flavor's doc, api/<flavor>/FrameScript.lua) and CreateAndInitFromMixin
-- (Interface/AddOns/Blizzard_SharedXMLBase/Mixin.lua:8-12 at the pinned live commit). The C bodies follow the Lua that
-- Mixin.lua shipped before they moved to C (Gethe/wow-ui-source a2be406dbd03, 11.0.0, :6-22): each mixin's fields are
-- copied in order onto the object, which is returned.
local M = {}

local TemplateApply = require("ui.template_apply")

local API_GATE = { gate = "api" }
-- Ketho's FrameXML list decides which flavors get it.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local function mixin(object, ...)
  for i = 1, select("#", ...) do
    TemplateApply.copyMixin(object, (select(i, ...)))
  end

  return object
end

local function createFromMixins(...)
  return mixin({}, ...)
end

-- Mixin.lua:8-12 calls the CreateFromMixins it captured at load, not the global an addon may replace.
local function createAndInitFromMixin(source, ...)
  local object = createFromMixins(source)
  object:Init(...)

  return object
end

function M.install(w)
  w:install("Mixin", mixin, API_GATE)
  w:install("CreateFromMixins", createFromMixins, API_GATE)
  w:install("CreateAndInitFromMixin", createAndInitFromMixin, KETHO_GATE)
end

return M

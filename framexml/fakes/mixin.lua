-- Mixin and CreateFromMixins (C APIs in every flavor's doc, api/<flavor>/FrameScript.lua) and CreateAndInitFromMixin
-- (Interface/AddOns/Blizzard_SharedXMLBase/Mixin.lua:8-12 at the pinned live commit). The C bodies follow the Lua that
-- Mixin.lua shipped before they moved to C (Gethe/wow-ui-source a2be406dbd03, 11.0.0, :6-22): each mixin's fields are
-- copied in order onto the object, which is returned.
local M = {}

local Callsite = require("ui.callsite")
local TemplateApply = require("ui.template_apply")

-- Localized: addon code may assign a global named select.
local select = select

local API_GATE = { gate = "api" }
-- Ketho's FrameXML list decides which flavors get it.
local KETHO_GATE = { gate = "framexml", flavors = {} }

-- The doc gives mixins Nilable = false (framescriptdocumentation.lua:322-336); the client's message text is not
-- documented, so the kit's argument format stands in. offset counts the arguments before the mixins.
-- source: assumed (row F7)
local function copyAll(w, name, offset, object, ...)
  for i = 1, select("#", ...) do
    local mixinTable = (select(i, ...))
    if type(mixinTable) ~= "table" then
      local message = "%s: bad argument #%d 'mixins' (table expected, got %s) on %s"
      error(message:format(name, i + offset, type(mixinTable), w.flavor), Callsite.level())
    end
    TemplateApply.copyMixin(object, mixinTable)
  end

  return object
end

function M.install(w)
  local function mixin(object, ...)
    return copyAll(w, "Mixin", 1, object, ...)
  end

  local function createFromMixins(...)
    return copyAll(w, "CreateFromMixins", 0, {}, ...)
  end

  -- Mixin.lua:8-12 calls the CreateFromMixins it captured at load, not the global an addon may replace.
  local function createAndInitFromMixin(source, ...)
    local object = createFromMixins(source)
    object:Init(...)

    return object
  end

  w:install("Mixin", mixin, API_GATE)
  w:install("CreateFromMixins", createFromMixins, API_GATE)
  w:install("CreateAndInitFromMixin", createAndInitFromMixin, KETHO_GATE)
end

return M

-- FrameXML fakes: kit stand-ins for the Blizzard UI globals addons read at load time. Each module in a stage
-- list exports install(w); adding a fake module is one line in its stage list.
local M = {}

local Widgets = require("ui.widgets")

-- Order matters: core creates UIParent before anything parents to it; menu_frames creates the DropDownList frames, so it
-- runs before frames (the lazy _G lookup), which goes last.
local STAGE1 = {
  "framexml.fakes.core",
  "framexml.fakes.mixin",
  "framexml.fakes.backdrop",
  "framexml.fakes.minimap",
  "framexml.fakes.colors",
  "framexml.fakes.color_util",
  "framexml.fakes.strings",
  "framexml.fakes.format_util",
  "framexml.fakes.table_util",
  "framexml.fakes.callbacks",
  "framexml.fakes.faux_scroll",
  "framexml.fakes.static_popup",
  "framexml.fakes.client",
  "framexml.fakes.slash",
  "framexml.fakes.tooltip",
  "framexml.fakes.frame_globals",
  "framexml.fakes.menu_frames",
  "framexml.fakes.dropdown",
  "framexml.fakes.menu",
  "framexml.fakes.scrolling_message_frame",
  "framexml.fakes.frames",
}

-- Installs the widgets (when not yet installed) and the stage-1 fakes into w.
function M.installStage1(w)
  if not w.ui then
    Widgets.install(w)
  end
  require("input").install(w)
  for _, name in ipairs(STAGE1) do
    require(name).install(w)
  end
end

return M

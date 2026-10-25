-- Texture:SetAtlas. The arguments are stored as the generic setter stores them (st.values.Atlas, which GetAtlas and the
-- render snapshot read); with a client extract, useAtlasSize also sizes the texture to the atlas row. Methods are
-- fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Client = require("client")

local methods = {}
M.methods = methods

local select = select

function methods.SetAtlas(w, obj, st, ...)
  st.values.Atlas = { n = select("#", ...), ... }
  local atlas, useAtlasSize = ...
  local row = useAtlasSize and w.client and type(atlas) == "string" and Client.atlas(w.client, atlas)
  if row then
    obj:SetSize(row.width, row.height)
  end
end

return M

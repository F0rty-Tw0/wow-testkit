-- The one place the render snapshot reads st.values[key], the generic store behind every SetX with no hand-written
-- method. A Phase 6 task that moves a method out of the generic store keeps its key readable here or patches this file.
local M = {}

local BehaviourTexture = require("ui.behaviour_texture")

local DEFAULT_ALPHA = 1

-- The args of the last SetKey call as a pack { n, ... }, or nil when it was never called.
function M.stored(st, key)
  return st.values[key]
end

-- The texture state st.tex ({ file, atlas, color, texCoord, vertexColor, gradient, blend, desaturated, rotation, horizTile,
-- vertTile }, each key only once set) of a texture, an empty table for one nothing was set on.
M.texture = BehaviourTexture.read

-- { r, g, b, a } from a list or pack of numbers (alpha 1 when absent); a copy of default when pack is nil.
function M.color(pack, default)
  if pack then
    return { pack[1], pack[2], pack[3], pack[4] or DEFAULT_ALPHA }
  elseif default then
    return { default[1], default[2], default[3], default[4] }
  end
  return nil
end

return M

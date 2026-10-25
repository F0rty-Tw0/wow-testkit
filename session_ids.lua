-- Ids of the render snapshot (render_fields.lua `f<seq>` frame, `t<seq>` texture, `s<seq>` font string, seq = st.seq) in
-- both directions: the id of a widget, and the widget behind an id.
local M = {}

local PREFIX = { frame = "f", texture = "t", fontstring = "s" }
local KIND_OF_TYPE = { Texture = "texture", FontString = "fontstring" }

-- "frame", "texture" or "fontstring" for a widget's state; nil for anything else a world tracks.
local function kindOf(st)
  if st.plan.isFrame then
    return "frame"
  end
  return KIND_OF_TYPE[st.plan.type]
end

-- The snapshot id of obj, or nil when obj is not a frame, texture or font string of the world.
function M.of(w, obj)
  local st = type(obj) == "table" and w.ui.state[obj]
  local kind = st and kindOf(st)
  return kind and PREFIX[kind] .. st.seq or nil
end

-- The widget a snapshot id names, or nil for an unknown id or text that is no id.
function M.find(w, id)
  local prefix, digits = tostring(id):match("^([fts])(%d+)$")
  if not prefix then
    return nil
  end
  local seq = tonumber(digits)
  for obj, st in pairs(w.ui.state) do
    local kind = kindOf(st)
    if st.seq == seq and kind and PREFIX[kind] == prefix then
      return obj
    end
  end
  return nil
end

return M

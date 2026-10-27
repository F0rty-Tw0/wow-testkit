-- The texture region that fills a named slot of a widget (a Button state role, a Slider thumb, a StatusBar bar). A slot
-- region is marked in its ui state under keys.mark (the slot name) and keys.owned (set when the widget made it itself,
-- which is hidden again when the slot is freed). Both users keep their slots in a table of their own state; keys is
-- { mark = ..., owned = ... }.
local M = {}

function M.isTexture(w, value)
  local st = type(value) == "table" and w.ui.state[value]

  return st and st.plan.isA.texture == true
end

-- The region filling slot of obj, or nil once another widget took it (re-parented it away). source: assumed (W18,
-- W43) a region another widget adopted no longer fills this widget's slot.
function M.held(w, slots, slot, obj)
  local region = slots[slot]
  if region and w.ui.state[region].parent == obj then
    return region
  end
end

-- Frees slot: the region stops filling it, and one the widget made is hidden. A region another widget took keeps its
-- marks, since they are that widget's now.
function M.release(w, obj, slots, slot, keys)
  local old = M.held(w, slots, slot, obj)
  slots[slot] = nil
  if not old then
    return
  end
  local oldState = w.ui.state[old]
  oldState[keys.mark] = nil
  if oldState[keys.owned] then
    oldState[keys.owned] = nil
    old:Hide()
  end
end

function M.claim(w, slots, slot, region, owned, keys)
  slots[slot] = region
  local regionState = w.ui.state[region]
  regionState[keys.mark] = slot
  regionState[keys.owned] = owned or nil
end

return M

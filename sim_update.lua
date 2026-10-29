-- SimUpdate: the client's per-frame OnUpdate. Walks the shown frames depth first and calls the OnUpdate script of each
-- frame that holds one (SetScript or HookScript).
local M = {}

local function hasOnUpdate(w, frame)
  local byName = w.scripts[frame]
  local entry = byName and byName.OnUpdate

  return entry ~= nil and (entry.fn ~= nil or #entry.hooks > 0)
end

local function copyList(list)
  local copy = {}
  for i, item in ipairs(list) do
    copy[i] = item
  end

  return copy
end

-- Frames with no parent, in creation order.
local function roots(w)
  local list = {}
  for _, frame in pairs(w.ui.bySeq) do
    local st = w.ui.state[frame]
    if st and st.plan.isFrame and not st.parent then
      list[#list + 1] = frame
    end
  end
  table.sort(list, function(a, b)
    return w.ui.state[a].seq < w.ui.state[b].seq
  end)

  return list
end

local function walk(w, frame, elapsed)
  local st = w.ui.state[frame]
  if not st.shown then
    return 0
  end
  local count = 0
  if hasOnUpdate(w, frame) then
    w:callScript(frame, "OnUpdate", elapsed)
    count = 1
  end
  for _, child in ipairs(copyList(st.children)) do
    count = count + walk(w, child, elapsed)
  end

  return count
end

-- source: assumed (spec 4.4) one OnUpdate call per sim step, with the whole step as elapsed, not one per 1/60 frame.
-- Returns how many OnUpdate scripts ran.
function M.run(w, elapsed)
  local count = 0
  for _, frame in ipairs(roots(w)) do
    count = count + walk(w, frame, elapsed)
  end

  return count
end

return M

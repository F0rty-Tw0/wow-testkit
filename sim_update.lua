-- SimUpdate: the client's per-frame OnUpdate. Walks the shown frames depth first and calls the OnUpdate script of each
-- frame that holds one (SetScript or HookScript).
-- The cost follows the frames that hold an OnUpdate (w.onUpdate, kept by world_events), not all frames: the walk
-- descends only into those and their ancestors.
local M = {}

local function hasOnUpdate(w, frame)
  local byName = w.scripts[frame]
  local entry = byName and byName.OnUpdate

  return entry ~= nil and (entry.fn ~= nil or #entry.hooks > 0)
end

-- The set of frames holding an OnUpdate and all their ancestors, and its roots (frames with no parent) in creation
-- order. A frame whose handler is gone (SetScript nil) leaves w.onUpdate. The set is fixed for the pass: a handler set
-- during it first runs on the next step.
local function mark(w)
  local state = w.ui.state
  local marked, roots = {}, {}
  for frame in pairs(w.onUpdate) do
    if hasOnUpdate(w, frame) then
      local node = frame
      while node and not marked[node] do
        marked[node] = true
        local st = state[node]
        if st and not st.parent and st.plan.isFrame then
          roots[#roots + 1] = node
        end
        node = st and st.parent
      end
    else
      w.onUpdate[frame] = nil
    end
  end
  table.sort(roots, function(a, b)
    return state[a].seq < state[b].seq
  end)

  return marked, roots
end

local function walk(w, frame, elapsed, marked)
  local st = w.ui.state[frame]
  if not st.shown then
    return 0
  end
  local count = 0
  if hasOnUpdate(w, frame) then
    w:callScript(frame, "OnUpdate", elapsed)
    count = 1
  end
  -- Copied, as the script may add, remove or move children.
  local kids = {}
  for _, child in ipairs(st.children) do
    if marked[child] then
      kids[#kids + 1] = child
    end
  end
  for _, child in ipairs(kids) do
    count = count + walk(w, child, elapsed, marked)
  end

  return count
end

-- source: assumed (spec 4.4) one OnUpdate call per sim step, with the whole step as elapsed, not one per 1/60 frame.
-- Returns how many OnUpdate scripts ran.
function M.run(w, elapsed)
  local count = 0
  local marked, roots = mark(w)
  for _, frame in ipairs(roots) do
    count = count + walk(w, frame, elapsed, marked)
  end

  return count
end

return M

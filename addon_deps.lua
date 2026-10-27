-- Dependency-ordered addon loading: the order a TOC's dependency directives give, and the load of that order through
-- Addon.load. Addons are found by folder name under one addons directory, the way the client finds them.
local M = {}

local Addon = require("addon")
local Toc = require("toc")
local fs = require("fs")

local BLIZZARD_PREFIX = "Blizzard_"

-- source: assumed (row G16) the addons directory is the parent of the addon's folder; "." has no readable parent name,
-- so its parent is "..". Backslashes are slashes, trailing ones dropped.
function M.addonsDirOf(root)
  local path = root:gsub("\\", "/"):gsub("/+$", "")
  if path == "." then
    return ".."
  end
  local parent = path:match("^(.*)/[^/]*$")
  if parent == nil then
    return "."
  end
  return parent == "" and "/" or parent
end

-- The metadata of name's TOC for flavor ({} when it cannot be read: Addon.load reports that).
local function metaOf(root, name, flavor)
  local text = fs.readFile(Toc.select(root, name, flavor))
  return text and Toc.parse(text).meta or {}
end

-- source: assumed (row G16) a cycle reads A -> B -> A, starting at the addon the walk met twice.
local function cycleReason(stack, name)
  local from = 1
  for i, item in ipairs(stack) do
    if item == name then
      from = i
    end
  end
  local path = {}
  for i = from, #stack do
    path[#path + 1] = stack[i]
  end
  path[#path + 1] = name
  return "dependency cycle: " .. table.concat(path, " -> ")
end

-- opts: { name, root, addonsDir? = the parent of root, flavor, provided? = fn(name) true for a dependency satisfied
-- without a folder }. Returns entries = { { name, root, required }, ... } with each addon's required dependencies first,
-- then its optional ones (each depth first), and the addon last; required is true for the addon and for each entry
-- reached through required dependencies only. Or returns nil and why it cannot load: "missing dependency: <name>" or
-- "dependency cycle: A -> B -> A". A dependency listed twice loads once.
function M.order(opts)
  local addonsDir = opts.addonsDir or M.addonsDirOf(opts.root)
  local entries, done, visiting, stack = {}, {}, {}, {}
  local entryOf = {}
  local visit
  -- source: assumed (row G16) a Blizzard_ dependency is satisfied without loading and is not listed; an absent
  -- optional dependency is ignored; a required one that is absent blocks the addon unless opts.provided answers for it.
  local function visitAll(names, required, viaRequired)
    for _, dep in ipairs(names) do
      local root = addonsDir .. "/" .. dep
      if dep:sub(1, #BLIZZARD_PREFIX) ~= BLIZZARD_PREFIX then
        if Toc.exists(root, dep) then
          local reason = visit(dep, root, required and viaRequired)
          if reason then
            return reason
          end
        elseif required and not (opts.provided and opts.provided(dep)) then
          return "missing dependency: " .. dep
        end
      end
    end
  end
  function visit(name, root, required)
    if done[name] then
      entryOf[name].required = entryOf[name].required or required
      return nil
    end
    if visiting[name] then
      return cycleReason(stack, name)
    end
    visiting[name] = true
    stack[#stack + 1] = name
    local deps = Toc.dependencies(metaOf(root, name, opts.flavor))
    local reason = visitAll(deps.required, true, required) or visitAll(deps.optional, false, required)
    if reason then
      return reason
    end
    stack[#stack] = nil
    visiting[name], done[name] = nil, true
    entryOf[name] = { name = name, root = root, required = required }
    entries[#entries + 1] = entryOf[name]
    return nil
  end
  local reason = visit(opts.name, opts.root, true)
  if reason then
    return nil, reason
  end
  return entries
end

local function skipped(reason)
  return { status = "skipped", reason = reason, report = {} }
end

-- w.mock.addons[name] after a load: loaded, with the TOC metadata the addon APIs read. A world without the game-state
-- mock keeps no such record.
local function record(w, entry)
  if w.mock then
    w.mock.addons = w.mock.addons or {}
    local known = w.mock.addons[entry.name] or {}
    known.loaded, known.meta = true, entry.info.meta
    w.mock.addons[entry.name] = known
  end
end

local function isLoaded(w, name)
  local known = w.mock and w.mock.addons and w.mock.addons[name]
  return type(known) == "table" and known.loaded == true
end

-- Loads M.order(opts) (flavor = w's) under the caller's context through Addon.load and calls afterEach(entry) after
-- each addon that loads; entry = { name, ns, info }. A dependency w.mock.addons already holds as loaded is not loaded
-- again, and satisfies a required dependency that has no folder. The last entry is the addon itself. A dependency that
-- comes back skipped stops the addon only when it is required; an optional one is passed over. When the addon cannot
-- load (the order failed, a required dependency came back skipped, or its own TOC skips it) its info is skipped with a
-- reason: "missing dependency: X", "dependency cycle: A -> B -> A" or "dependency X not loadable: <its reason>", and
-- afterEach is not called for it.
function M.loadAll(w, opts, afterEach)
  local order, reason = M.order({
    name = opts.name,
    root = opts.root,
    addonsDir = opts.addonsDir,
    flavor = w.flavor,
    provided = function(dep)
      return isLoaded(w, dep)
    end,
  })
  if not order then
    return { { name = opts.name, ns = {}, info = skipped(reason) } }
  end
  local entries = {}
  for i, item in ipairs(order) do
    local isAddon = i == #order
    if isAddon or not isLoaded(w, item.name) then
      local ns, info = Addon.load(w, item)
      local entry = { name = item.name, ns = ns, info = info }
      if info.status == "skipped" and not isAddon and item.required then
        local why = "dependency " .. item.name .. " not loadable: " .. info.reason
        entries[#entries + 1] = { name = opts.name, ns = {}, info = skipped(why) }
        return entries
      end
      -- source: assumed (row G16) an optional dependency that cannot load is passed over; the addon still loads.
      local passedOver = info.status == "skipped" and not isAddon
      if not passedOver then
        entries[#entries + 1] = entry
      end
      if info.status ~= "skipped" then
        record(w, entry)
        afterEach(entry)
      end
    end
  end
  return entries
end

return M

-- Loads an addon into a world the way the client does: picks and parses the TOC for the world's flavor, then runs
-- each Lua file as chunk(name, ns) in one per-addon environment. A file that fails to compile or errors at load goes
-- to the error handler (by default w.errors) and loading continues with the next file.
local M = {}

local Flavors = require("tools.flavors")
local Toc = require("toc")
local fs = require("fs")

local NOT_DECLARED = "not-declared"
local NIL_REQUIRE = "attempt to call a nil value (global 'require')"
-- WoW: Forever has a global require that rejects addon module names.
local FOREVER_REQUIRE = "Invalid import"

local function requireSentinel(flavor)
  local message = flavor == "forever" and FOREVER_REQUIRE or NIL_REQUIRE
  return function()
    error(message, 2)
  end
end

-- Reads fall through to _G; writes land in _G (raw, so w:destroy's snapshot removes them). The require sentinel
-- is raw in the environment, so it shadows any host require.
local function newEnv(flavor)
  local env = setmetatable({}, {
    __index = _G,
    __newindex = function(_, key, value)
      rawset(_G, key, value)
    end,
  })
  rawset(env, "require", requireSentinel(flavor))
  return env
end

-- Reads a TOC- or XML-listed file. A missing one is a packaging bug in the addon, so it is an error.
local function readListed(w, ctx, relative)
  local text = fs.readFile(ctx.root .. "/" .. relative)
  if not text then
    w:reportError("TOC lists missing file: addon:" .. ctx.name .. "/" .. relative)
  end
  return text
end

local function runFile(w, ctx, relative)
  local source = readListed(w, ctx, relative)
  if not source then
    ctx.report[#ctx.report + 1] = relative .. ": cannot read file; skipped"
    return
  end
  local chunkName = "addon:" .. ctx.name .. "/" .. relative
  w:registerChunk(chunkName)
  local chunk, loadErr = loadstring(source, "@" .. chunkName)
  if not chunk then
    w:reportError(loadErr)
    return
  end
  setfenv(chunk, ctx.env)
  w:callAsAddon(chunk, ctx.name, ctx.ns)
end

local function versionNote(declared, flavor)
  local row = Flavors.get(flavor)
  return string.format("TOC interface is %s for %s (client %d); loaded anyway", declared, flavor, row.tocVersion)
end

-- opts: { name, root }. Returns ns, info = { status = "loaded"|"skipped", reason, toc, declared, report,
-- savedVariables, savedVariablesPerCharacter }.
function M.load(w, opts)
  local name, root = opts.name, opts.root
  local tocPath = Toc.select(root, name, w.flavor)
  local parsed = Toc.parse(assert(fs.readFile(tocPath), "cannot read TOC " .. tocPath))
  local info = {
    toc = tocPath,
    declared = Toc.declared(parsed.meta, w.flavor),
    report = {},
    savedVariables = parsed.savedVariables,
    savedVariablesPerCharacter = parsed.savedVariablesPerCharacter,
  }
  local ns = {}
  if info.declared == NOT_DECLARED then
    info.status, info.reason = "skipped", "not declared"
    return ns, info
  end
  info.status = "loaded"
  local ctx = { name = name, root = root, ns = ns, env = newEnv(w.flavor) }
  local files, report = Toc.filesFor(parsed, w.flavor, function(path)
    return readListed(w, ctx, path)
  end)
  info.report, ctx.report = report, report
  if info.declared ~= "load" then
    table.insert(report, 1, versionNote(info.declared, w.flavor))
  end
  for _, relative in ipairs(files) do
    runFile(w, ctx, relative)
  end
  return ns, info
end

-- Sets each SavedVariables / SavedVariablesPerCharacter global from saved[name] (nil when absent).
function M.applySaved(w, info, saved)
  saved = saved or {}
  for _, names in ipairs({ info.savedVariables, info.savedVariablesPerCharacter }) do
    for _, name in ipairs(names) do
      w:setGlobal(name, saved[name])
    end
  end
end

return M

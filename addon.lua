-- Loads an addon into a world the way the client does: picks and parses the TOC for the world's flavor, then runs
-- each Lua file as chunk(name, ns) in one per-addon environment. A file that fails to compile or errors at load goes
-- to the error handler (by default w.errors) and loading continues with the next file.
local M = {}

local AddonEnv = require("addon_env")
local Flavors = require("tools.flavors")
local Toc = require("toc")
local Xml = require("ui.xml")
local fs = require("fs")

local NOT_DECLARED = "not-declared"

-- Reads a TOC- or XML-listed file. A missing one is a packaging bug in the addon, so it is an error.
local function readListed(w, ctx, relative)
  local text = fs.readFile(ctx.root .. "/" .. relative)
  if not text then
    w:reportError("TOC lists missing file: addon:" .. ctx.name .. "/" .. relative)
  end
  return text
end

-- Compiles source as chunkName in the addon's environment. A syntax error goes to the error handler (nil returned).
local function compile(w, ctx, source, chunkName)
  w:registerChunk(chunkName)
  local chunk, loadErr = loadstring(source, "@" .. chunkName)
  if not chunk then
    w:reportError(loadErr)
    return nil
  end
  return setfenv(chunk, ctx.env)
end

-- Compiles source as chunkName and runs it as the addon, in the addon's environment.
local function runChunk(w, ctx, source, chunkName)
  local chunk = compile(w, ctx, source, chunkName)
  if chunk then
    w:callAsAddon(chunk, ctx.name, ctx.ns)
  end
end

-- Runs a TOC- or XML-listed Lua file, relative to the addon root.
function M.runFile(w, ctx, relative)
  local source = readListed(w, ctx, relative)
  if not source then
    ctx.report[#ctx.report + 1] = relative .. ": cannot read file; skipped"
    return
  end
  runChunk(w, ctx, source, "addon:" .. ctx.name .. "/" .. relative)
end

-- Source that sits at `line` of its file: the padding makes an error name that line, not line 1.
local function padded(source, line)
  return string.rep("\n", line - 1) .. source
end

-- The per-addon load context: { name, root, ns, env, report, readFile(relative) -> text | nil, runFile(relative),
-- runSource(source, chunkName, line), compile(source, chunkName, line) -> chunk | nil (the chunk is not run) }. report is the list of what the kit ignored; M.load replaces it with the TOC's.
function M.context(w, name, root)
  local ctx = { name = name, root = root, ns = {}, env = AddonEnv.newEnv(w), report = {} }
  function ctx.readFile(relative)
    return readListed(w, ctx, relative)
  end
  function ctx.runFile(relative)
    M.runFile(w, ctx, relative)
  end
  function ctx.runSource(source, chunkName, line)
    runChunk(w, ctx, padded(source, line), chunkName)
  end
  function ctx.compile(source, chunkName, line)
    return compile(w, ctx, padded(source, line), chunkName)
  end
  return ctx
end

-- Loads one TOC-listed file at its position: XML builds its frames, Lua runs as a chunk.
local function loadListed(w, ctx, relative)
  if relative:lower():match("%.xml$") then
    Xml.loadFile(w, relative, ctx)
  else
    M.runFile(w, ctx, relative)
  end
end

local function versionNote(declared, flavor)
  local row = Flavors.get(flavor)
  return string.format("TOC interface is %s for %s (client %d); loaded anyway", declared, flavor, row.tocVersion)
end

-- True when root holds a TOC for name on any flavor (a flavor-suffixed one or the bare <name>.toc).
local function hasAnyToc(root, name)
  for _, flavor in ipairs(Flavors.list) do
    if fs.exists(Toc.select(root, name, flavor)) then
      return true
    end
  end
  return false
end

-- opts: { name, root }. Returns ns, info = { status = "loaded"|"skipped", reason, toc, declared, report,
-- savedVariables, savedVariablesPerCharacter }. No TOC for this flavor but one for another: skipped, with only
-- status, reason and report. No TOC for the name at all: an error.
function M.load(w, opts)
  local name, root = opts.name, opts.root
  local tocPath = Toc.select(root, name, w.flavor)
  if not fs.exists(tocPath) and hasAnyToc(root, name) then
    return {}, { status = "skipped", reason = "no TOC for this flavor", report = {} }
  end
  local parsed = Toc.parse(assert(fs.readFile(tocPath), "cannot read TOC " .. tocPath))
  local info = {
    toc = tocPath,
    declared = Toc.declared(parsed.meta, w.flavor),
    report = {},
    savedVariables = parsed.savedVariables,
    savedVariablesPerCharacter = parsed.savedVariablesPerCharacter,
  }
  if info.declared == NOT_DECLARED then
    info.status, info.reason = "skipped", "not declared"
    return {}, info
  end
  info.status = "loaded"
  local ctx = M.context(w, name, root)
  local files, report = Toc.filesFor(parsed, w.flavor)
  info.report, ctx.report = report, report
  if info.declared ~= "load" then
    table.insert(report, 1, versionNote(info.declared, w.flavor))
  end
  for _, relative in ipairs(files) do
    loadListed(w, ctx, relative)
  end
  return ctx.ns, info
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

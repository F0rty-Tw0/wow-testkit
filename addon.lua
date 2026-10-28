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

-- collectgarbage, held here so addon code assigning the global cannot reach it; a field so tests can watch the pause.
M.gc = collectgarbage

-- The load-time clock: os.clock, the one debugprofilestop reads (luaext.lua); a field so tests can fake it.
M.clock = os.clock

-- Reads a TOC- or XML-listed file. A missing one is a packaging bug in the addon, so it is an error.
local function readListed(w, ctx, relative)
  local text = fs.readFile(ctx.root .. "/" .. relative)
  if not text then
    w:reportError("TOC lists missing file: addon:" .. ctx.name .. "/" .. relative)
  end
  return text
end

-- Compiles source as chunkName in the addon's environment. A syntax error, or a precompiled chunk, goes to the error
-- handler (nil returned).
local function compile(w, ctx, source, chunkName)
  w:registerChunk(chunkName)
  local refusal = AddonEnv.binaryRefusal(source)
  if refusal then
    w:reportError(chunkName .. ": " .. refusal)
    return nil
  end
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

-- Runs a TOC- or XML-listed Lua file, relative to the addon root, read through ctx.readFile.
function M.runFile(w, ctx, relative)
  local source = ctx.readFile(relative)
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

-- The per-addon load context: { name, root, ns, env, report, readFile(relative) -> text | nil, exists(relative),
-- runFile(relative), runSource(source, chunkName, line), compile(source, chunkName, line) -> chunk | nil (the chunk is
-- not run) }. report is the list of what the kit ignored; M.load replaces it with the TOC's.
function M.context(w, name, root)
  local ctx = { name = name, root = root, ns = {}, env = AddonEnv.newEnv(w), report = {} }
  function ctx.readFile(relative)
    return readListed(w, ctx, relative)
  end
  function ctx.exists(relative)
    return fs.exists(ctx.root .. "/" .. relative)
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

local function loadEach(w, ctx, files)
  for _, relative in ipairs(files) do
    loadListed(w, ctx, relative)
  end
end

-- Loads the TOC's files in order with w.dev.loading naming the addon, then appends { name, loadMs, memoryKb } to
-- w.dev.loads: kit CPU time (M.clock) and heap growth, an estimate (no forced collection, which would shift GC timing),
-- floored at 0 because an addon's own collectgarbage("collect") frees garbage older than its load. The outermost load
-- restarts the GC, also when a file raises.
local function loadFiles(w, ctx, files)
  local dev = w.dev
  local outer = dev.loading
  -- GC paused: a cycle ending mid-load frees older garbage and would hide this load's growth.
  M.gc("stop")
  local startClock, startKb = M.clock(), M.gc("count")
  dev.loading = ctx.name
  local ok, err = pcall(loadEach, w, ctx, files)
  local loadMs = (M.clock() - startClock) * 1000
  local memoryKb = math.max(0, M.gc("count") - startKb)
  dev.loading = outer
  if outer == nil then
    M.gc("restart")
  end
  if not ok then
    error(err, 0)
  end
  dev.loads[#dev.loads + 1] = { name = ctx.name, loadMs = loadMs, memoryKb = memoryKb }
end

local function versionNote(declared, flavor)
  local row = Flavors.get(flavor)
  return string.format("TOC interface is %s for %s (client %d); loaded anyway", declared, flavor, row.tocVersion)
end

-- opts: { name, root }. Returns ns, info = { status = "loaded"|"skipped", reason, toc, meta, declared, report,
-- savedVariables, savedVariablesPerCharacter }. No TOC for this flavor but one for another: skipped, with only
-- status, reason and report. No TOC for the name at all: an error.
function M.load(w, opts)
  local name, root = opts.name, opts.root
  local tocPath = Toc.select(root, name, w.flavor)
  if not fs.exists(tocPath) and Toc.exists(root, name) then
    return {}, { status = "skipped", reason = "no TOC for this flavor", report = {} }
  end
  local parsed = Toc.parse(assert(fs.readFile(tocPath), "cannot read TOC " .. tocPath))
  local info = {
    toc = tocPath,
    meta = parsed.meta,
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
  loadFiles(w, ctx, files)
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

-- { [name] = value } of the SavedVariables / SavedVariablesPerCharacter globals the TOC names (nil values omitted). The
-- world is the active one, so its globals are _G (applySaved's counterpart; _w only keeps the two signatures alike).
function M.collectSaved(_w, info)
  local saved = {}
  for _, names in ipairs({ info.savedVariables or {}, info.savedVariablesPerCharacter or {} }) do
    for _, name in ipairs(names) do
      saved[name] = rawget(_G, name)
    end
  end
  return saved
end

return M

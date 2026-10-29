-- The Blizzard UI layer (Ruling R7): Blizzard's own UI addons, read from a client extract and loaded through the
-- kit's loader before the addon under test, with the kit's fakes standing in for the C API. Opt-in (Scenario
-- opts.blizzardUi); with no extract it loads nothing and says so. Blizzard code runs secure (w.taint.secureAddons) and
-- its errors, at load and for the rest of the world's life, go to w.blizzard.errors instead of failing the addon under
-- test.
local M = {}

local Addon = require("addon")
local AddonDeps = require("addon_deps")
local Bindings = require("bindings")
local Flavors = require("tools.flavors")
local Toc = require("toc")
local TocHeader = require("toc_header")
local Xml = require("ui.xml")
local fs = require("fs")

-- Localized: addon code may assign a global named debug.
local debugTraceback = debug.traceback

-- The client's spelling: Blizzard Lua compares addon names exactly.
M.TARGETS = { "Blizzard_ActionBar", "Blizzard_UnitFrame", "Blizzard_EditMode" }
-- source: assumed (row BU1) the default key bindings per flavor, under <extract.dir>/code/. The extract has no
-- bindings.xml: Blizzard_FrameXML holds one unlisted file per game type.
M.BINDINGS_FILES = {
  retail = "addons/blizzard_framexml/bindings_standard.xml",
  mists = "addons/blizzard_framexml/bindings_mists.xml",
}

local ENGINE = "blizzard"
local FRAMEXML = "Blizzard_FrameXML"
local NO_EXTRACT = "Blizzard UI: no client extract; kit fakes only"
local NO_BINDINGS = "Blizzard UI: no default Bindings.xml"
local FIRST_ERRORS = 10
local ADDON_SOURCE = "^addon:([^/\r\n]+)/"
-- ADDON_LOADED payload: addOnName, containsBindings.
local CONTAINS_BINDINGS = false

-- The TOC the client reads for name on flavor in root, whose files are all lowercase; nil when there is none.
local function tocOf(root, name, flavor)
  for _, suffix in ipairs(Flavors.get(flavor).tocSuffixes) do
    local path = root .. "/" .. (name .. suffix):lower() .. ".toc"
    if fs.exists(path) then
      return path
    end
  end
  local path = root .. "/" .. name:lower() .. ".toc"
  return fs.exists(path) and path or nil
end

-- Returns entries, skipped, notes: entries = { { name, root, parsed }, ... } with each addon's required dependencies
-- first, then its optional ones (depth first, each once), then the addon; skipped = { { name, reason = "not in
-- extract" } } for each target or dependency the extract lacks (the others still load). A dependency the flavor does not load is
-- left out (Toc.dependencies); a cycle is cut and noted. name keeps the spelling of the target or of the TOC line that
-- named it; root, file reads and the once-only check use name:lower().
function M.order(extract, targets, flavor)
  local entries, skipped, notes, done, visiting = {}, {}, {}, {}, {}
  local function visit(name)
    local key = name:lower()
    if visiting[key] then
      notes[#notes + 1] = "Blizzard UI: dependency cycle at " .. name .. "; cut"
      return
    elseif done[key] then
      return
    end
    done[key] = true
    local root = extract.dir .. "/code/addons/" .. key
    local toc = tocOf(root, name, flavor)
    if not toc then
      skipped[#skipped + 1] = { name = name, reason = "not in extract" }
      return
    end
    local parsed = Toc.parse(fs.readFile(toc) or "")
    if not TocHeader.loadsOn(parsed.meta, flavor) then
      skipped[#skipped + 1] = { name = name, reason = "game type" }
      return
    end
    visiting[key] = true
    local deps = Toc.dependencies(parsed.meta, flavor)
    for _, list in ipairs({ deps.required, deps.optional }) do
      for _, dep in ipairs(list) do
        visit(dep)
      end
    end
    visiting[key] = nil
    entries[#entries + 1] = { name = name, root = root, parsed = parsed }
  end
  for _, name in ipairs(targets) do
    visit(name)
  end
  return entries, skipped, notes
end

-- The addon chunk a position starts with ("addon:<name>/...", or Lua's "...<tail>" for a long chunk name, resolved
-- against w.chunks; the cut can fall inside "addon:"): its addon name, or nil.
local function addonAt(w, text)
  local tail = text:match("^%.%.%.([^\r\n]-):%d+:")
  if not tail then
    return text:match(ADDON_SOURCE)
  end
  for chunk in pairs(w.chunks) do
    if chunk:sub(-#tail) == tail then
      return chunk:match(ADDON_SOURCE)
    end
  end
  return nil
end

-- The Blizzard addon an error belongs to: the addon its message names, else the innermost addon chunk on the stack (a
-- kit error raised under Blizzard code); nil when that addon is not a Blizzard one.
local function blame(w, message)
  local name = addonAt(w, message)
  if not name then
    for line in debugTraceback():gmatch("\n%s*([^\n]+)") do
      name = addonAt(w, line)
      if name then
        break
      end
    end
  end
  return name and w.taint.secureAddons[name] and name or nil
end

-- From now on an error Blizzard code raises goes to report.errors as { addon, message }; any other error goes to the
-- handler w had. Returns the new handler: Blizzard_ScriptErrors replaces it through seterrorhandler while it loads, and
-- M.load puts it back.
local function keepErrors(w, report)
  local original = w.errorHandler
  w.errorHandler = function(message)
    local addon = blame(w, tostring(message))
    if not addon then
      return original(message)
    end
    report.errors[#report.errors + 1] = { addon = addon, message = tostring(message) }
  end
  return w.errorHandler
end

-- ctx.readFile for an extract addon: TOC lines and XML paths are mixed case and the extract is lowercase. A file the
-- extract lacks is a note, not an error. A UTF-8 BOM the client skips is dropped by Addon.runFile and Xml, for every addon.
-- source: assumed (row BU11) "..\..\..\Interface\AddOns\<Addon>\X" is the client's game-root path to an addon folder (tbc
-- Blizzard_MapCanvas.xml:3); the extract keeps addons side by side, so it reads "../<addon>/X".
local function lowerPath(relative)
  return (relative:gsub("\\", "/"):lower():gsub("^%.%./%.%./%.%./interface/addons/", "../"))
end

local function lowerReader(root, name, notes)
  return function(relative)
    local path = lowerPath(relative)
    local text = fs.readFile(root .. "/" .. path)
    if not text then
      notes[#notes + 1] = "Blizzard UI: " .. name .. " lists missing file " .. path
    end
    return text
  end
end

-- source: assumed (row BU3) "[Family]\X.lua" and "[Game]\X.lua" in a Blizzard TOC: the family folder is the flavor's
-- last TOC suffix (Mainline, Classic), the game folder its first (Standard, Mists).
local function withFolders(path, flavor)
  local suffixes = Flavors.get(flavor).tocSuffixes
  local folders = { family = suffixes[#suffixes], game = suffixes[1] }
  return (path:gsub("%[(%a+)%]", function(token)
    local suffix = folders[token:lower()]
    return suffix and (suffix:gsub("^[_%-]", ""))
  end))
end

-- Runs entry's TOC files for w's flavor, registers its bindings.xml, records it as loaded and fires ADDON_LOADED.
local function loadEntry(w, entry, report, fire)
  local ctx = Addon.context(w, entry.name, entry.root)
  ctx.readFile = lowerReader(entry.root, entry.name, report.notes)
  function ctx.exists(relative)
    return fs.exists(entry.root .. "/" .. lowerPath(relative))
  end
  for _, listed in ipairs((Toc.filesFor(entry.parsed, w.flavor))) do
    local path = withFolders(listed, w.flavor)
    if path:lower():match("%.xml$") then
      Xml.loadFile(w, path, ctx)
    else
      Addon.runFile(w, ctx, path)
    end
  end
  local bindings = fs.readFile(entry.root .. "/bindings.xml")
  if bindings then
    Bindings.loadXml(w, bindings, entry.name)
  end
  AddonDeps.record(w, { name = entry.name, info = { meta = entry.parsed.meta } })
  report.loaded[#report.loaded + 1] = entry.name
  fire("ADDON_LOADED", entry.name, CONTAINS_BINDINGS)
end

local function loadDefaultBindings(w, extract, report)
  local relative = M.BINDINGS_FILES[w.flavor]
  local path = relative and extract.dir .. "/code/" .. relative
  local text = path and fs.readFile(path)
  if not text then
    report.notes[#report.notes + 1] = NO_BINDINGS
    return
  end
  Bindings.loadXml(w, text, FRAMEXML)
  report.defaultBindings = path
end

local function isLoaded(report, name)
  local key = name:lower()
  for _, loaded in ipairs(report.loaded) do
    if loaded:lower() == key then
      return true
    end
  end
  return false
end

-- Loads opts.targets (default M.TARGETS) and their dependencies from extract into w, in M.order, after the flavor's
-- default bindings file; opts.fire(event, ...) fires ADDON_LOADED (default w:fire). Returns the report, also stored as
-- w.blizzard: { loaded = { name... }, errors = { { addon, message } }, skipped = { { name, reason } }, notes,
-- defaultBindings = path | nil }. extract nil: nothing loads, one note.
function M.load(w, extract, opts)
  opts = opts or {}
  local report = { loaded = {}, errors = {}, skipped = {}, notes = {} }
  w.blizzard = report
  if not extract then
    report.notes[1] = NO_EXTRACT
    return report
  end
  local fire = opts.fire or function(...)
    w:fire(...)
  end
  local entries
  entries, report.skipped, report.notes = M.order(extract, opts.targets or M.TARGETS, w.flavor)
  local secure = w.taint.secureAddons
  secure[FRAMEXML] = true
  for _, entry in ipairs(entries) do
    secure[entry.name] = true
  end
  report.handler = keepErrors(w, report)
  loadDefaultBindings(w, extract, report)
  -- source: assumed (row B3) nothing reloads: an ADDON_LOADED handler may have loaded an entry through LoadAddOn.
  for _, entry in ipairs(entries) do
    if not isLoaded(report, entry.name) then
      loadEntry(w, entry, report, fire)
      w.errorHandler = report.handler
    end
  end
  return report
end

local function append(target, list)
  for _, item in ipairs(list) do
    target[#target + 1] = item
  end
end

-- Loads name (and the dependencies M.order puts first, those already loaded skipped) into w after M.load ran and fires
-- ADDON_LOADED(<name as the caller spelled it>, false) for each addon it loads. Its errors go to the caller's handler,
-- kept after each load: w.blizzard.errors while that is the layer's, else a user addon's seterrorhandler (assumed).
-- Returns true, also when name was already loaded (B3: nothing reloads); nil, "MISSING" when the extract has no such
-- addon or the layer is off.
function M.loadOne(w, name)
  local report, extract = w.blizzard, w.client
  if not (report and extract) then
    return nil, "MISSING"
  elseif isLoaded(report, name) then
    return true
  end
  local entries, skipped, notes = M.order(extract, { name }, w.flavor)
  local last = entries[#entries]
  if not (last and last.name == name) then
    return nil, "MISSING"
  end
  append(report.skipped, skipped)
  append(report.notes, notes)
  for _, entry in ipairs(entries) do
    if not isLoaded(report, entry.name) then
      w.taint.secureAddons[entry.name] = true
      local handler = w.errorHandler
      loadEntry(w, entry, report, function(...)
        w:run(ENGINE, w.fire, w, ...)
      end)
      w.errorHandler = handler
    end
  end
  return true
end

-- { enabled, loaded, errors = <count>, firstErrors = { { addon, message }... up to 10 }, notes }; enabled is false
-- when the layer never ran in w.
function M.summary(w)
  local report = w.blizzard
  if not report then
    return { enabled = false, loaded = {}, errors = 0, firstErrors = {}, notes = {} }
  end
  local first = {}
  for i = 1, math.min(FIRST_ERRORS, #report.errors) do
    first[i] = report.errors[i]
  end
  return { enabled = true, loaded = report.loaded, errors = #report.errors, firstErrors = first, notes = report.notes }
end

return M

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
-- source: row BU25 (confirmed) Blizzard_ChatFrame makes ChatFrame1 and Blizzard_CompactRaidFrames makes CompactPartyFrame,
-- which the classic frame position manager (uiparentpanelmanageroverrides.lua:73, :100) and Edit Mode
-- (EditModeSystemTemplates.lua:1517) index; the client loads both at login, so neither may be nil.
-- source: row BU27 (confirmed) Blizzard_QueueStatusFrame makes QueueStatusButton, which Edit Mode indexes
-- (EditModeSystemTemplates.lua:2467); it loads at login, and on forever no other target's dependency names it.
-- source: row BU28 (confirmed) Blizzard_GameMenu makes GameMenuFrame, which the panel manager's IsOptionFrameOpen indexes
-- unguarded (tbc uiparentpanelmanager.lua:1140, reached from ToggleAllBags); it loads at login.
-- source: row BU29 (confirmed) Blizzard_MainMenuBarBagButtons makes MainMenuBarBackpackButton, which the classic bag frame
-- checks on open (tbc containerframe_shared.lua:270); it loads at login.
-- source: row BU31 (confirmed) Blizzard_TokenUI and Blizzard_Statistics make TokenFrame and StatisticsFrame, which the
-- camelot character frame hides unguarded (forever camelot/characterframe.lua:113); both load at login.
-- source: row BU32 (confirmed) Blizzard_AuraContainer defines ManagedAuraContainerSharedMixin, which forever's
-- Blizzard_UnitFrame reads at load (shared/targetframeauracontainer.lua:15); no TOC depends on it, it loads at login
-- (no LoadOnDemand, AllowLoad game). First, so it loads before the unit frames (assumed: the client's order agrees).
-- source: row BU33 (confirmed) Blizzard_AutoComplete defines AUTOCOMPLETE_LIST, which tbc Blizzard_UIPanels_Game's XML
-- OnLoads index (classic/mailframe.xml:584, friendsframe.xml:4373); the action bar's dependencies load UIPanels_Game and
-- only the chat and popup addons depend on AutoComplete, so it loaded after. First too (assumed: the client's order agrees).
M.TARGETS = {
  "Blizzard_AutoComplete",
  "Blizzard_AuraContainer",
  "Blizzard_ActionBar",
  "Blizzard_UnitFrame",
  "Blizzard_EditMode",
  "Blizzard_OverrideActionBar",
  "Blizzard_ChatFrame",
  "Blizzard_CompactRaidFrames",
  "Blizzard_QueueStatusFrame",
  "Blizzard_GameMenu",
  "Blizzard_MainMenuBarBagButtons",
  "Blizzard_TokenUI",
  "Blizzard_Statistics",
}
-- source: assumed (row BU1) the default key bindings per flavor, under <extract.dir>/code/. The extract has no
-- bindings.xml: Blizzard_FrameXML holds one unlisted file per game type.
M.BINDINGS_FILES = {
  retail = "addons/blizzard_framexml/bindings_standard.xml",
  mists = "addons/blizzard_framexml/bindings_mists.xml",
  tbc = "addons/blizzard_framexml/bindings_tbc.xml",
  vanilla = "addons/blizzard_framexml/bindings_vanilla.xml",
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

-- The addon's name for its lowercase folder dir: the TOC Title when it spells dir, else the start of a file line that
-- does ("Blizzard_PlayerSpells_Bootstrap.lua"), else dir. Assumed (row BU30): Blizzard file names begin with the addon's.
local function spelling(dir, parsed)
  local title = parsed.meta.Title
  if title and title:lower() == dir then
    return title
  end
  for _, file in ipairs(parsed.files) do
    local start = file.path:match("[^/]*$"):sub(1, #dir)
    if start:lower() == dir then
      return start
    end
  end
  return dir
end

-- { { name, root, parsed }, ... }: the extract's addons that load on flavor, in folder order (name per spelling).
local function extractAddons(extract, flavor)
  local addons, base = {}, extract.dir .. "/code/addons"
  for _, dir in ipairs(fs.isdir(base) and fs.list(base) or {}) do
    local root = base .. "/" .. dir
    local toc = tocOf(root, dir, flavor)
    local parsed = toc and Toc.parse(fs.readFile(toc) or "")
    if parsed and TocHeader.loadsOn(parsed.meta, flavor) then
      addons[#addons + 1] = { name = spelling(dir, parsed), root = root, parsed = parsed }
    end
  end
  return addons
end

-- { [lowercase trigger] = { name, ... } }: the extract's addons that load on flavor and whose LoadWith names the trigger,
-- in folder order.
local function loadWithIndex(extract, flavor)
  local index = {}
  for _, addon in ipairs(extractAddons(extract, flavor)) do
    for _, trigger in ipairs(Toc.loadWith(addon.parsed.meta, flavor)) do
      local key = trigger:lower()
      index[key] = index[key] or {}
      index[key][#index[key] + 1] = addon.name
    end
  end
  return index
end

-- Returns entries, skipped, notes: entries = { { name, root, parsed }, ... } with each addon's required dependencies
-- first, then its optional ones (depth first, each once), then the addon, then the addons whose LoadWith names it
-- (row G37); skipped = { { name, reason = "not in extract" } } for each target or dependency the extract lacks (the
-- others still load). A dependency the flavor does not load is left out (Toc.dependencies); a cycle is cut and noted.
-- name keeps the spelling of the target or of the TOC line that named it; root, file reads and the once-only check use
-- name:lower().
function M.order(extract, targets, flavor)
  local entries, skipped, notes, done, visiting = {}, {}, {}, {}, {}
  local loadWith = loadWithIndex(extract, flavor)
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
    local loads, reason = TocHeader.loadsOn(parsed.meta, flavor)
    if not loads then
      skipped[#skipped + 1] = { name = name, reason = reason }
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
    for _, follower in ipairs(loadWith[key] or {}) do
      visit(follower)
    end
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

-- Runs files (TOC paths) of entry in a load context of its own.
local function runFiles(w, entry, files, report)
  local ctx = Addon.context(w, entry.name, entry.root)
  ctx.readFile = lowerReader(entry.root, entry.name, report.notes)
  function ctx.exists(relative)
    return fs.exists(entry.root .. "/" .. lowerPath(relative))
  end
  for _, path in ipairs(files) do
    if path:lower():match("%.xml$") then
      Xml.loadFile(w, path, ctx)
    else
      Addon.runFile(w, ctx, path)
    end
  end
end

-- Runs entry's TOC files for w's flavor ([Family] and [Game] expanded by Toc.filesFor, row BU3), registers its
-- bindings.xml, records it as loaded and fires ADDON_LOADED.
local function loadEntry(w, entry, report, fire)
  runFiles(w, entry, (Toc.filesFor(entry.parsed, w.flavor)), report)
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

-- source: row BU30, Toc.bootstrapFiles: after the targets, each LoadOnDemand addon of the extract not loaded yet runs its
-- [Bootstrap] lines (folder order, assumed); its code is Blizzard's, so it runs secure and its errors are the layer's.
local function runBootstraps(w, extract, report)
  for _, addon in ipairs(extractAddons(extract, w.flavor)) do
    local files = Toc.bootstrapFiles(addon.parsed, w.flavor)
    if #files > 0 and not isLoaded(report, addon.name) then
      w.taint.secureAddons[addon.name] = true
      runFiles(w, addon, files, report)
      w.errorHandler = report.handler
    end
  end
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
  runBootstraps(w, extract, report)
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

-- Addon APIs over w.mock: addons = { [name] = { loaded, enabled, meta } } and addonsDir. The installed addons are the
-- folders of addonsDir that hold a TOC (listed in name order) plus every name the mock holds; an addon's fields come from
-- the mock, else from its TOC for the world's flavor. A mock entry that is not a table (false clears one) is no entry.
-- Loading one on demand goes through AddonDeps, so its dependencies load first. Only the C_AddOns names are installed: no flavor has the bare globals (row G1).
local M = {}

local AddonDeps = require("addon_deps")
local BlizzardUi = require("blizzard_ui")
local State = require("game.state")
local Toc = require("toc")
local WorldApi = require("world_api")
local fs = require("fs")
local define = State.define

local ENGINE = "blizzard"
local BLIZZARD_PREFIX = "Blizzard_"
-- source: assumed (row G15) every addon is INSECURE: the kit models no secure addons.
local SECURITY = "INSECURE"

M.DEFAULTS = { addons = {} }

-- Sorted names of the folders of dir that hold a TOC of their own name.
local function scan(dir)
  local names = {}
  for _, name in ipairs(fs.list(dir)) do
    if Toc.exists(dir .. "/" .. name, name) then
      names[#names + 1] = name
    end
  end
  return names
end

-- The addon lookups for one world: the folder scan is read once per directory.
local function newCatalog(w)
  local scanned = { dir = nil, names = {} }
  local catalog = {}

  -- Sorted names of the installed addons.
  function catalog.names()
    local dir = w.mock.addonsDir
    if dir and scanned.dir ~= dir then
      scanned.dir, scanned.names = dir, scan(dir)
    end
    local seen, names = {}, {}
    for _, name in ipairs(dir and scanned.names or {}) do
      seen[name] = true
      names[#names + 1] = name
    end
    for name, held in pairs(w.mock.addons) do
      if not seen[name] and type(held) == "table" then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    return names
  end

  -- The installed addon an index (1-based, in name order) or a name stands for, or nil. source: assumed (row G16) a
  -- dependency check treats a Blizzard_ addon as present, so the call api asked about one the mock does not hold counts
  -- unscripted.
  function catalog.resolve(ident, api)
    local name = catalog.find(ident)
    if not name and type(ident) == "string" and ident:sub(1, #BLIZZARD_PREFIX) == BLIZZARD_PREFIX then
      WorldApi.markUnscripted(w, api)
    end
    return name
  end

  -- catalog.resolve without the unscripted count.
  function catalog.find(ident)
    local names = catalog.names()
    if type(ident) == "number" then
      return names[ident]
    end
    for _, name in ipairs(names) do
      if name == ident then
        return name
      end
    end
    return nil
  end

  -- The mock's record of name; false (how a patch clears an addon) and nil are no record.
  function catalog.state(name)
    local held = w.mock.addons[name]
    return type(held) == "table" and held or {}
  end

  function catalog.enabled(name)
    return catalog.state(name).enabled ~= false
  end

  -- The TOC fields: the mock's meta, else the TOC for the world's flavor ({} when the addon has no folder).
  function catalog.meta(name)
    local meta = catalog.state(name).meta
    if meta then
      return meta
    end
    local dir = w.mock.addonsDir
    local text = dir and fs.readFile(Toc.select(dir .. "/" .. name, name, w.flavor))
    return text and Toc.parse(text).meta or {}
  end

  return catalog
end

local function installQueries(w, catalog)
  -- source: confirmed (row G15) loadedOrLoading, loaded; the kit has no loading state, so both are the same.
  define(w, "C_AddOns.IsAddOnLoaded", function(ident)
    local name = catalog.resolve(ident, "C_AddOns.IsAddOnLoaded")
    local loaded = name ~= nil and catalog.state(name).loaded == true
    return loaded, loaded
  end)
  -- source: confirmed (row G15) nil for a field the TOC lacks.
  define(w, "C_AddOns.GetAddOnMetadata", function(ident, field)
    local name = catalog.resolve(ident, "C_AddOns.GetAddOnMetadata")
    return name and catalog.meta(name)[field] or nil
  end)
  define(w, "C_AddOns.GetNumAddOns", function()
    return #catalog.names()
  end)
  -- source: confirmed (row G15) name, title, notes, loadable, reason, security; assumed the title is the folder name
  -- without a Title field, reason is DISABLED for a disabled addon and nil otherwise, and security is INSECURE.
  define(w, "C_AddOns.GetAddOnInfo", function(ident)
    local name = catalog.resolve(ident, "C_AddOns.GetAddOnInfo")
    if not name then
      return nil
    end
    local meta, enabled = catalog.meta(name), catalog.enabled(name)
    return name, meta.Title or name, meta.Notes, enabled, not enabled and "DISABLED" or nil, SECURITY
  end)
end

local function installEnableFlags(w, catalog)
  local function setEnabled(api, enabled)
    define(w, api, function(ident)
      local name = catalog.resolve(ident, api)
      if name then
        local state = catalog.state(name)
        state.enabled = enabled
        w.mock.addons[name] = state
      end
    end)
  end
  setEnabled("C_AddOns.EnableAddOn", true)
  setEnabled("C_AddOns.DisableAddOn", false)
end

-- source: assumed (row G15) the reason codes of a load that fails: DEP_MISSING for a missing dependency,
-- DEP_INCOMPATIBLE for one that does not load on the flavor, INCOMPATIBLE for the addon itself.
local function loadFailure(reason)
  if reason:find("^missing dependency") then
    return "DEP_MISSING"
  elseif reason:find("^dependency %S+ not loadable") then
    return "DEP_INCOMPATIBLE"
  end
  return "INCOMPATIBLE"
end

local function installLoad(w, catalog)
  -- source: assumed (row G15) true once loaded, or nil and MISSING (not installed), DISABLED or a loadFailure code; a
  -- loaded addon answers true without loading again; an addon the mock holds without a folder is loaded as it stands.
  -- A Blizzard_ addon the catalog does not hold goes to the Blizzard UI layer when it is on: it loads from the extract
  -- with its dependencies (B3; assumed); one the extract lacks too answers as the catalog does (MISSING).
  define(w, "C_AddOns.LoadAddOn", function(ident)
    if w.blizzard and type(ident) == "string" and ident:match("^[Bb]lizzard_") and not catalog.find(ident) then
      if BlizzardUi.loadOne(w, ident) then
        return true
      end
    end
    local name = catalog.resolve(ident, "C_AddOns.LoadAddOn")
    if not name then
      return nil, "MISSING"
    elseif not catalog.enabled(name) then
      return nil, "DISABLED"
    elseif catalog.state(name).loaded then
      return true
    end
    local dir = w.mock.addonsDir
    if not (dir and Toc.exists(dir .. "/" .. name, name)) then
      w.mock.addons[name].loaded = true
      return true
    end
    local entries = AddonDeps.loadAll(w, { name = name, root = dir .. "/" .. name, addonsDir = dir }, function(entry)
      w:run(ENGINE, w.fire, w, "ADDON_LOADED", entry.name, false)
    end)
    local info = entries[#entries].info
    if info.status == "skipped" then
      return nil, loadFailure(info.reason)
    end
    return true
  end)
end

function M.install(w)
  local catalog = newCatalog(w)
  installQueries(w, catalog)
  installEnableFlags(w, catalog)
  installLoad(w, catalog)
  -- source: confirmed (row G15) ReloadUI is FrameXML on every flavor and reloads the interface; assumed the kit raises a
  -- flag (a session reloads on it) and Logout and Quit end nothing.
  define(w, "ReloadUI", function()
    w.reloadRequested = true
  end, State.ALL)
  define(w, "Logout", function() end)
  define(w, "Quit", function() end)
end

return M

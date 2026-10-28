-- WTF import: the SavedVariables files of a real client (WTF/Account/<NAME>/SavedVariables/<Addon>.lua and the
-- character's own) read into the saved table a session starts from, and the folder's CVars, key bindings and Edit Mode
-- layouts put into a world. Each SavedVariables file runs in an empty environment, so it can set globals and nothing
-- else; bytecode is refused. Nothing here writes to the WTF folders or reads outside the one it opens.
local M = {}

local Bindings = require("bindings")
local EditModeCache = require("session_wtf_editmode")
local SessionOptions = require("session_options")
local SessionSaved = require("session_saved")
local Toc = require("toc")
local fs = require("fs")

-- Localized: addon code may assign globals with these names.
local ipairs, loadstring, pairs, pcall, setfenv, tostring = ipairs, loadstring, pairs, pcall, setfenv, tostring

local PRECOMPILED = "\27"

-- The globals text sets when run in a fresh empty environment, or nil plus why it did not run.
local function run(text, label)
  if text:sub(1, 1) == PRECOMPILED then
    return nil, "bytecode refused"
  end
  local chunk, err = loadstring(text, "=wtf:" .. label)
  if not chunk then
    return nil, err
  end
  local env = {}
  local ok, runErr = pcall(setfenv(chunk, env))
  if not ok then
    return nil, runErr
  end

  return env
end

-- Copies the globals in names that the file at path sets into saved. A file that cannot be read or run adds one warning
-- to warnings and is skipped.
local function readFile(path, label, names, saved, warnings)
  local text = fs.readFile(path)
  if not text then
    warnings[#warnings + 1] = "wtf: cannot read " .. path
    return
  end
  local env, err = run(text, label)
  if not env then
    warnings[#warnings + 1] = "wtf: " .. path .. ": " .. tostring(err)
    return
  end
  for _, name in ipairs(names) do
    saved[name] = env[name]
  end
end

-- The saved table of an addon's WTF files and the warnings for the files that did not load. info is the addon's TOC
-- info (savedVariables, savedVariablesPerCharacter); files is { account?, character? } absolute paths. A file keeps only
-- the names the TOC lists for its kind.
function M.read(info, files)
  local saved, warnings = {}, {}
  if files.account then
    readFile(files.account, "account", info.savedVariables, saved, warnings)
  end
  if files.character then
    readFile(files.character, "character", info.savedVariablesPerCharacter, saved, warnings)
  end
  return saved, warnings
end

-- Reads files for the addon in opts.addonDir (its TOC on the flavor opts opens on, no world needed) and stores the
-- result as opts.sessionDir's saved.lua. Returns the warnings; an addon without a TOC writes nothing.
function M.seed(opts, files)
  local root = opts.addonDir
  local name, nameErr = Toc.addonName(root)
  if not name then
    return { "wtf: " .. nameErr }
  end
  local tocPath = Toc.select(root, name, SessionOptions.flavorOf(opts))
  local text = fs.readFile(tocPath)
  if not text then
    return { "wtf: cannot read " .. tocPath }
  end
  local saved, warnings = M.read(Toc.parse(text), files)
  SessionSaved.write(opts.sessionDir, saved)

  return warnings
end

local SAVED_DIR = "SavedVariables"
-- source: assumed (row BU6) a character with no active layout in its file starts on the first saved layout.
local DEFAULT_ACTIVE = 3

-- The path of dir's entry called name ignoring case, or nil.
local function entryOf(dir, name)
  local wanted = name:lower()
  for _, entry in ipairs(fs.list(dir)) do
    if entry:lower() == wanted then
      return dir .. "/" .. entry
    end
  end
  return nil
end

-- The account folder names under dir/Account, sorted; the account-wide SavedVariables folder and files are left out.
function M.accounts(dir)
  local base, names = dir .. "/Account", {}
  for _, name in ipairs(fs.list(base)) do
    local account = name:lower() ~= SAVED_DIR:lower() and fs.isdir(base .. "/" .. name)
    names[#names + 1] = account and name or nil
  end

  return names
end

local function pickAccount(dir, wanted)
  local names = M.accounts(dir)
  for _, name in ipairs(wanted and names or {}) do
    if name:lower() == wanted:lower() then
      return name
    end
  end
  if wanted or #names == 0 then
    return nil, "no account " .. (wanted and wanted .. " " or "") .. "in " .. dir .. "/Account"
  elseif #names > 1 then
    return nil, "several accounts: " .. table.concat(names, ", ") .. "; pass --wtf-account"
  end

  return names[1]
end

-- Lines `SET <name> "<value>"` as { [lowercase name] = value }; every other line is ignored.
function M.parseConfig(text)
  local cvars = {}
  for line in text:gmatch("[^\r\n]+") do
    local name, value = line:match('^SET (%S+) "(.*)"$')
    if name then
      cvars[name:lower()] = value
    end
  end

  return cvars
end

-- The CVars of the config files at paths (nil entries skipped), a later file winning.
local function cvarsOf(paths)
  local cvars = {}
  for i = 1, table.maxn(paths) do
    local text = paths[i] and fs.readFile(paths[i])
    for name, value in pairs(text and M.parseConfig(text) or {}) do
      cvars[name] = value
    end
  end

  return cvars
end

-- Sets wtf.editMode (nil when no layouts are saved) and wtf.activeLayout from the account and character files.
local function readEditMode(wtf, accountDir, characterDir)
  local path = accountDir .. "/edit-mode-cache-account.txt"
  local text = fs.readFile(path)
  if not text then
    return
  end
  local layouts, reason = EditModeCache.parseLayouts(text)
  if not layouts then
    wtf.warnings[#wtf.warnings + 1] = "wtf: " .. path .. ": " .. reason
  end
  wtf.editMode = layouts and #layouts > 0 and layouts or nil
  local active = wtf.editMode and characterDir and fs.readFile(characterDir .. "/edit-mode-cache-character.txt")
  wtf.activeLayout = active and EditModeCache.parseActive(active, #layouts) or nil
end

local function savedFile(dir, addon)
  local saved = dir and entryOf(dir, SAVED_DIR)

  return saved and entryOf(saved, addon .. ".lua")
end

-- Reads the WTF folder dir for opts = { account?, realm?, character? } (the account may be left out when dir holds
-- one). Returns wtf = { dir, account, realm?, character?, cvars = { [lowercase name] = value }, bindings = text?,
-- editMode = { layoutInfo... }?, activeLayout?, warnings, filesFor(addon) -> { account?, character? } paths of the
-- addon's SavedVariables files }, or nil and why not. CVars merge Config.wtf, the account's and the character's
-- config-cache.wtf, a later file winning.
function M.open(dir, opts)
  opts = opts or {}
  if not fs.isdir(dir) then
    return nil, "no WTF folder at " .. dir
  end
  local account, err = pickAccount(dir, opts.account)
  if not account then
    return nil, err
  end
  local accountDir = dir .. "/Account/" .. account
  local realmDir = opts.realm and entryOf(accountDir, opts.realm)
  local characterDir = realmDir and opts.character and entryOf(realmDir, opts.character)
  if opts.character and not characterDir then
    return nil, "no character " .. tostring(opts.realm) .. "/" .. opts.character .. " in account " .. account
  end
  local wtf = { dir = dir, account = account, realm = opts.realm, character = opts.character, warnings = {} }
  local configs = { dir .. "/Config.wtf", accountDir .. "/config-cache.wtf", characterDir and characterDir .. "/config-cache.wtf" }
  wtf.cvars = cvarsOf(configs)
  wtf.bindings = fs.readFile(accountDir .. "/bindings-cache.wtf") or nil
  readEditMode(wtf, accountDir, characterDir)
  function wtf.filesFor(addon)
    return { account = savedFile(accountDir, addon), character = savedFile(characterDir, addon) }
  end

  return wtf
end

-- A host's opts.wtfDir (with wtfAccount?, wtfCharacter? = "Realm/Character"): the whole WTF folder the Python host was
-- given. Opens it into opts.wtfData (Session applies it before each login) and opts.wtf (the addon's SavedVariables
-- files, Wtf.read). Returns the warnings; a folder that cannot be opened is one warning and no import.
function M.openOptions(opts)
  if not opts.wtfDir then
    return {}
  end
  local realm, character = (opts.wtfCharacter or ""):match("^(.-)/(.+)$")
  local wtf, err = M.open(opts.wtfDir, { account = opts.wtfAccount, realm = realm, character = character })
  if not wtf then
    return { "wtf: " .. err }
  end
  opts.wtfData = wtf
  opts.wtf = wtf.filesFor(Toc.addonName(opts.addonDir) or "")

  return wtf.warnings
end

-- Puts a Wtf.open table into w: its CVars, its key bindings (after Bindings.install) and its layouts with the active
-- one (DEFAULT_ACTIVE when the character file names none).
function M.apply(w, wtf)
  w:setMock({ cvars = wtf.cvars })
  if wtf.bindings then
    Bindings.loadWtf(w, wtf.bindings)
  end
  if wtf.editMode then
    w:setMock({ editMode = { layouts = wtf.editMode, active = wtf.activeLayout or DEFAULT_ACTIVE } })
  end
end

return M

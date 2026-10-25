-- WTF import: the SavedVariables files of a real client (WTF/Account/<NAME>/SavedVariables/<Addon>.lua and the
-- character's own) read into the saved table a session starts from. Each file runs in an empty environment, so it can
-- set globals and nothing else; bytecode is refused. Nothing here writes to the WTF folders.
local M = {}

local SessionOptions = require("session_options")
local SessionSaved = require("session_saved")
local Toc = require("toc")
local fs = require("fs")

-- Localized: addon code may assign globals with these names.
local ipairs, loadstring, pcall, setfenv, tostring = ipairs, loadstring, pcall, setfenv, tostring

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

return M

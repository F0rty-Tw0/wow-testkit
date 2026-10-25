-- Key bindings: which command a key runs. w.bindings = { keys = { [KEY] = command }, overrides = { [owner] = { [KEY] =
-- { command, priority, seq } } }, commands = { [NAME] = { chunk, runOnUp } }, seq }. The kit implements the SetBinding
-- family; the user's bindings-cache.wtf fills keys and an addon's Bindings.xml fills commands. Blizzard's own
-- Bindings.xml is not loaded here (it calls Blizzard Lua that exists only in the opt-in layer).
local M = {}

local Addon = require("addon")
local Input = require("input")
local XmlParse = require("ui.xml_parse")
local fs = require("fs")

local unpack = unpack

local DEFAULT_BUTTON = "LeftButton"
local CLICK = "CLICK"
local XML_FILE = "Bindings.xml"

-- Binding tables -------------------------------------------------------------------------------------------------

local function clickCommand(frameName, mouseButton)
  return CLICK .. " " .. frameName .. ":" .. (mouseButton or DEFAULT_BUTTON)
end

local function bind(w, key, command)
  w.bindings.keys[key:upper()] = command
  return true
end

local function bindOverride(w, owner, priority, key, command)
  local byOwner = w.bindings.overrides[owner] or {}
  w.bindings.overrides[owner] = byOwner
  key = key:upper()
  if command == nil then
    byOwner[key] = nil
    return
  end
  w.bindings.seq = w.bindings.seq + 1
  byOwner[key] = { command = command, priority = priority and true or false, seq = w.bindings.seq }
end

-- source: assumed (K3) a priority override beats a plain one, and the later of two equal overrides wins.
local function ranksAbove(entry, best)
  if entry.priority ~= best.priority then
    return entry.priority
  end
  return entry.seq > best.seq
end

-- The command an override binding gives key, or nil.
local function overrideFor(w, key)
  local best
  for _, byKey in pairs(w.bindings.overrides) do
    local entry = byKey[key]
    if entry and (not best or ranksAbove(entry, best)) then
      best = entry
    end
  end
  return best and best.command
end

-- source: assumed (K3) an override binding wins over a plain one.
-- The command key runs: an override's, else the plain binding's, else nil.
function M.lookup(w, key)
  key = key:upper()
  return overrideFor(w, key) or w.bindings.keys[key]
end

local function keysOf(w, command)
  local keys = {}
  for key, bound in pairs(w.bindings.keys) do
    if bound == command then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  return keys
end

-- The API ---------------------------------------------------------------------------------------------------------

local function api(w)
  return {
    SetBinding = function(key, command)
      return bind(w, key, command)
    end,
    SetBindingClick = function(key, buttonName, mouseButton)
      return bind(w, key, clickCommand(buttonName, mouseButton))
    end,
    GetBindingKey = function(command)
      return unpack(keysOf(w, command))
    end,
    GetBindingAction = function(key, checkOverride)
      local command = checkOverride and overrideFor(w, key:upper())
      return command or w.bindings.keys[key:upper()] or ""
    end,
    SetOverrideBinding = function(owner, isPriority, key, command)
      bindOverride(w, owner, isPriority, key, command)
    end,
    SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
      bindOverride(w, owner, isPriority, key, clickCommand(buttonName, mouseButton))
    end,
    ClearOverrideBindings = function(owner)
      w.bindings.overrides[owner] = nil
    end,
  }
end

function M.install(w)
  w.bindings = { keys = {}, overrides = {}, commands = {}, seq = 0 }
  for name, impl in pairs(api(w)) do
    w:install(name, impl, { gate = "api" })
  end
end

-- Loading ---------------------------------------------------------------------------------------------------------

-- Reads `bind <KEY> <COMMAND>` lines (the command is the rest of the line); every other line is ignored.
function M.loadWtf(w, text)
  for line in text:gmatch("[^\r\n]+") do
    local key, command = line:match("^%s*bind%s+(%S+)%s+(.-)%s*$")
    if key and command ~= "" then
      bind(w, key, command)
    end
  end
end

-- Loads the file at path (nil: none to load); returns true, or nil and the reason.
function M.loadFile(w, path)
  if not path then
    return true
  end
  local text = fs.readFile(path)
  if not text then
    return nil, "cannot read " .. path
  end
  M.loadWtf(w, text)
  return true
end

-- source: assumed (K3) a <Binding> body is a chunk run as the addon with the argument keystate ("down" or "up").
-- Registers each <Binding name="X">body</Binding> of text as w.bindings.commands.X.
function M.loadXml(w, text, addonName)
  local root, err = XmlParse.parse(text)
  if not root then
    w:reportError(addonName .. "/" .. XML_FILE .. ": " .. err)
    return
  end
  local ctx = Addon.context(w, addonName, "")
  local chunkName = "addon:" .. addonName .. "/" .. XML_FILE
  for _, node in ipairs(root.children) do
    local name = node.tag == "binding" and node.attrs.name
    local chunk = name and ctx.compile("local keystate = ...; " .. node.text, chunkName, node.textLine)
    if chunk then
      w.bindings.commands[name] = { chunk = chunk, runOnUp = node.attrs.runonup == "true" }
    end
  end
end

-- Loads <root>/Bindings.xml when the addon has one.
function M.loadAddon(w, addonName, root)
  local text = fs.readFile(root .. "/" .. XML_FILE)
  if text then
    M.loadXml(w, text, addonName)
  end
end

-- Running ----------------------------------------------------------------------------------------------------------

-- CLICK <FrameName>:<Button> clicks that frame, on key down only, unless the client would ignore the click.
local function clickBinding(w, target, keystate)
  local name, button = target:match("^(.-):(%S+)$")
  local frame = rawget(_G, name or target)
  if keystate == "up" or not Input.isFrame(w, frame) then
    return
  end
  button = button or DEFAULT_BUTTON
  if not Input.blockedReason(w, frame, "click", button) then
    Input.click(w, frame, button)
  end
end

-- source: assumed (K3) a command runs on key down with keystate "down"; one marked runOnUp runs on key up only, with
-- "up". A command the kit does not know (a spell, an action) does nothing.
function M.run(w, command, keystate)
  local target = command:match("^" .. CLICK .. "%s+(.+)$")
  if target then
    return clickBinding(w, target, keystate)
  end
  local entry = w.bindings.commands[command]
  if entry and entry.runOnUp == (keystate == "up") then
    w:callAsAddon(entry.chunk, keystate)
  end
end

return M

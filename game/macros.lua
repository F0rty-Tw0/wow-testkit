-- Macros kept in w.mock.macros = { account = {}, character = {} } (lists of { name, icon, body }) and the icon list in
-- w.mock.macroIcons. Account macros index from 1, character macros from MAX_ACCOUNT + 1. A macro the mock does not hold
-- returns the API's default and counts as unscripted. RunMacro and RunMacroText hand each slash line to w:slash, and
-- count as unscripted in a world without it.
local M = {}

local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

-- source: confirmed (row G17) the limits on retail and forever; assumed (row G17) 18 character macros on mists, tbc and
-- vanilla, no data holds the constant there.
local MAX_ACCOUNT = 120
local MAX_CHARACTER = { retail = 30, forever = 30 }
local MAX_CHARACTER_CLASSIC = 18

M.DEFAULTS = { macros = { account = {}, character = {} }, macroIcons = { 134400 } }

-- Returns list, position, index of the macro an index or a name stands for; nil when the mock holds none.
local function find(w, ident)
  local macros = w.mock.macros
  if type(ident) == "number" then
    if ident >= 1 and ident <= MAX_ACCOUNT then
      return macros.account[ident] and macros.account, ident, ident
    end
    local pos = ident - MAX_ACCOUNT
    return pos >= 1 and macros.character[pos] and macros.character, pos, ident
  end
  for _, kind in ipairs({ "account", "character" }) do
    for pos, macro in ipairs(macros[kind]) do
      if macro.name == ident then
        return macros[kind], pos, kind == "account" and pos or MAX_ACCOUNT + pos
      end
    end
  end
  return nil
end

local function installReads(w)
  -- Returns the macro and its index for ident, counting the call unscripted when the mock holds none.
  local function lookup(ident, name)
    local list, pos, index = find(w, ident)
    if not list then
      WorldApi.markUnscripted(w, name)
      return nil
    end
    return list[pos], index
  end
  -- source: confirmed (row G17) the two counts.
  define(w, "GetNumMacros", function()
    return #w.mock.macros.account, #w.mock.macros.character
  end)
  define(w, "GetMacroInfo", function(ident)
    local macro = lookup(ident, "GetMacroInfo")
    if macro then
      return macro.name, macro.icon, macro.body
    end
  end)
  define(w, "GetMacroBody", function(ident)
    local macro = lookup(ident, "GetMacroBody")
    return macro and macro.body
  end)
  -- source: confirmed (row G17) 0 when no slot holds the name.
  define(w, "GetMacroIndexByName", function(name)
    local _, index = lookup(name, "GetMacroIndexByName")
    return index or 0
  end)
end

local function installEdits(w)
  define(w, "CreateMacro", function(name, icon, body, perCharacter)
    local list = w.mock.macros[perCharacter and "character" or "account"]
    local limit = perCharacter and (MAX_CHARACTER[w.flavor] or MAX_CHARACTER_CLASSIC) or MAX_ACCOUNT
    if #list >= limit then
      WorldApi.markUnscripted(w, "CreateMacro")
      return nil
    end
    list[#list + 1] = { name = name, icon = icon, body = body }
    return perCharacter and MAX_ACCOUNT + #list or #list
  end)
  -- A nil name, icon or body keeps the macro's own.
  define(w, "EditMacro", function(ident, name, icon, body)
    local list, pos, index = find(w, ident)
    if not list then
      WorldApi.markUnscripted(w, "EditMacro")
      return nil
    end
    local macro = list[pos]
    macro.name, macro.icon, macro.body = name or macro.name, icon or macro.icon, body or macro.body
    return index
  end)
  define(w, "DeleteMacro", function(ident)
    local list, pos = find(w, ident)
    if list then
      table.remove(list, pos)
    else
      WorldApi.markUnscripted(w, "DeleteMacro")
    end
  end)
end

-- source: assumed (row G17) the text runs each line starting with a slash in turn and ignores the rest. A world without
-- w:slash (no framexml/fakes/slash.lua) cannot run a slash line, so the call counts as unscripted under name.
local function runText(w, text, name)
  local skipped = false
  for line in tostring(text):gmatch("[^\r\n]+") do
    local command = line:sub(1, 1) == "/"
    if command and w.slash then
      w:slash(line)
    elseif command then
      skipped = true
    end
  end
  if skipped then
    WorldApi.markUnscripted(w, name)
  end
end

local function installRun(w)
  -- source: confirmed (row G1) bare RunMacroText exists on no flavor; the C_Macro name is where the data has it.
  define(w, "C_Macro.RunMacroText", function(text)
    runText(w, text, "C_Macro.RunMacroText")
  end)
  define(w, "RunMacro", function(ident)
    local list, pos = find(w, ident)
    if list then
      runText(w, list[pos].body, "RunMacro")
    else
      WorldApi.markUnscripted(w, "RunMacro")
    end
  end)
end

-- source: assumed (row G17) one icon list serves both calls; each fills the table it is given and returns it.
local function installIcons(w)
  local function fill(icons)
    icons = icons or {}
    for i, icon in ipairs(w.mock.macroIcons) do
      icons[i] = icon
    end
    return icons
  end
  define(w, "GetMacroIcons", fill)
  define(w, "GetMacroItemIcons", fill)
end

function M.install(w)
  installReads(w)
  installEdits(w)
  installRun(w)
  installIcons(w)
end

return M

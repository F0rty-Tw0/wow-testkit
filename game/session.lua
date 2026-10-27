-- Session and client state: locale, realm, CVars, login, client platform, frame rate, network stats and the server
-- clock, all read from w.mock at call time.
local M = {}

local State = require("game.state")
local define, ALL = State.define, State.ALL

local floor = math.floor

M.DEFAULTS = {
  locale = "enUS",
  realm = "Kirin Tor",
  loggedIn = false,
  client = "windows",
  fps = 60,
  -- source: assumed (row G5) the kit values.
  net = { bandwidthIn = 0.5, bandwidthOut = 0.5, latencyHome = 30, latencyWorld = 40 },
  serverTime = 1790000000,
  cvars = {},
}

-- source: confirmed (row G3) SetCVar sends "1" or "0" for a boolean, else tostring(value); assumed (row G3) names are
-- case-insensitive, so keys are stored lowercase.
local function cvarKey(name)
  return type(name) == "string" and name:lower() or nil
end

local function toCvarValue(value)
  if type(value) == "boolean" then
    return value and "1" or "0"
  end
  return value ~= nil and tostring(value) or nil
end

local function installCvars(w)
  local function get(name)
    local key = cvarKey(name)
    return key and w.mock.cvars[key] or nil
  end
  local function getBool(name)
    return get(name) == "1"
  end
  local function set(name, value)
    local key = cvarKey(name)
    if not key then
      return false
    end
    w.mock.cvars[key] = toCvarValue(value)
    return true
  end
  define(w, "GetCVar", get, ALL)
  define(w, "GetCVarBool", getBool, ALL)
  define(w, "SetCVar", set, ALL)
  define(w, "C_CVar.GetCVar", get)
  define(w, "C_CVar.GetCVarBool", getBool)
  define(w, "C_CVar.SetCVar", set)
end

-- source: confirmed (row G2) GetNormalizedRealmName is the realm name without spaces, hyphens and periods.
local function installRealm(w)
  define(w, "GetLocale", function()
    return w.mock.locale
  end)
  define(w, "GetRealmName", function()
    return w.mock.realm
  end)
  define(w, "GetNormalizedRealmName", function()
    return (w.mock.realm:gsub("[ %-%.]", ""))
  end)
end

-- source: confirmed (row G5) GetNetStats returns four numbers; the data lists three and Validate checks arguments only.
local function installClient(w)
  define(w, "IsMacClient", function()
    return w.mock.client == "mac"
  end)
  define(w, "IsWindowsClient", function()
    return w.mock.client == "windows"
  end)
  define(w, "GetFramerate", function()
    return w.mock.fps
  end)
  define(w, "GetNetStats", function()
    local net = w.mock.net
    return net.bandwidthIn, net.bandwidthOut, net.latencyHome, net.latencyWorld
  end)
end

function M.install(w)
  -- source: confirmed (row G4) nil before PLAYER_LOGIN; assumed (row G4) true inside its handlers (Scenario:login sets
  -- w.mock.loggedIn just before the event).
  define(w, "IsLoggedIn", function()
    return w.mock.loggedIn or nil
  end)
  -- source: assumed (row G5) whole seconds that advance with the kit clock, counted from the world's start.
  local start = w.now
  define(w, "GetServerTime", function()
    return w.mock.serverTime + floor(w.now - start)
  end)
  installRealm(w)
  installCvars(w)
  installClient(w)
end

return M

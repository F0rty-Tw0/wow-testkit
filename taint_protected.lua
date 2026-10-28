-- Protected functions: the one gate (w.callGate, called by world_api.lua after argument validation) that refuses a tainted
-- call to a protected global function, a combat-only one in combat, and a secret argument a function does not accept
-- from that caller; and Protected.report, the one way a refusal is logged and announced (ADDON_ACTION_FORBIDDEN or
-- ADDON_ACTION_BLOCKED, the chat line and the popup the client shows with them).
local Callsite = require("ui.callsite")
local Data = require("taint_protected_data")
local Secret = require("combat_secret_value")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local pairs, rawget, error, pcall = pairs, rawget, error, pcall

-- source: assumed (row TS11) the text of INTERFACE_ACTION_BLOCKED and of the ADDON_ACTION_FORBIDDEN dialog; the client's
-- own are used when the strings are loaded.
local BLOCKED_TEXT = "Interface action failed because of an AddOn"
local FORBIDDEN_DIALOG = { text = "%s has been blocked from an action only available to the Blizzard UI.", button1 = "Disable", button2 = "Ignore" }
local SYSTEM_COLOR = { 1, 1, 0 }

local function copy(set)
  local out = {}
  for name in pairs(set) do
    out[name] = true
  end
  return out
end

-- source: assumed (row TS11) BLOCKED adds INTERFACE_ACTION_BLOCKED to DEFAULT_CHAT_FRAME as a system message, the first
-- time only; a world without DEFAULT_CHAT_FRAME (every world but a Session) has nowhere to show it.
local function showBlocked(w)
  local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
  if w.taint.blockedShown or not chat then
    return
  end
  w.taint.blockedShown = true
  local info = rawget(_G, "ChatTypeInfo")
  local color = info and info.SYSTEM or SYSTEM_COLOR
  chat:AddMessage(rawget(_G, "INTERFACE_ACTION_BLOCKED") or BLOCKED_TEXT, color.r or color[1], color.g or color[2], color.b or color[3])
end

-- source: assumed (row TS11) FORBIDDEN shows StaticPopup_Show("ADDON_ACTION_FORBIDDEN", addon, nil, addon); the kit
-- defines the dialog when no definition is loaded.
local function showForbidden(addon)
  local dialogs, show = rawget(_G, "StaticPopupDialogs"), rawget(_G, "StaticPopup_Show")
  if not (dialogs and show) then
    return
  end
  dialogs.ADDON_ACTION_FORBIDDEN = dialogs.ADDON_ACTION_FORBIDDEN or FORBIDDEN_DIALOG
  show("ADDON_ACTION_FORBIDDEN", addon, nil, addon)
end

-- Logs a refused call (kind "BLOCKED" or "FORBIDDEN", name as the client prints it, addon defaulting to the running
-- taint), fires the event and shows what the client shows. A refusal inside an ADDON_ACTION handler is logged only.
function M.report(w, kind, name, addon)
  local t = w.taint
  addon = addon or Taint.current(w) or ""
  local event = "ADDON_ACTION_" .. kind
  local text = name .. " blocked: execution tainted by " .. Taint.who(addon)
  Taint.record(w, { kind = "blocked", addon = addon, name = name, event = event, text = text })
  if t.reporting then
    return
  end
  t.reporting = true
  local ok, err = pcall(w.run, w, "blizzard", Taint.secure, w, function()
    w:fire(event, addon, name)
    if kind == "BLOCKED" then
      showBlocked(w)
    else
      showForbidden(addon)
    end
  end)
  t.reporting = false
  if not ok then
    error(err, 0)
  end
end

-- True when a tainted call to name was refused: a protected function always, a combat-only one in combat. Secure
-- callers pass.
function M.guardCall(w, name)
  local t = w.taint
  if not t.enforce or not Taint.current(w) then
    return false
  elseif t.protected[name] then
    M.report(w, "FORBIDDEN", name .. "()")
    return true
  elseif t.noCombat[name] and w.mock and w.mock.combat == true then
    M.report(w, "BLOCKED", name .. "()")
    return true
  end
  return false
end

-- source: assumed (row TS19) AllowedWhenUntainted refuses a secret from tainted code, NotAllowed from every caller,
-- AllowedWhenTainted never refuses; the refusal is an immediate Lua error, not an ADDON_ACTION path.
local function refuseSecret(w, name, signature, args)
  local mode = signature and signature.secret and signature.secret.args
  if mode == "NotAllowed" or (mode == "AllowedWhenUntainted" and Taint.current(w)) then
    for i = 1, args.n do
      if Secret.is(args[i]) then
        error(name .. ": secret argument " .. (mode == "NotAllowed" and "not allowed" or "from tainted code"), Callsite.level())
      end
    end
  end
end

function M.install(w)
  local t = w.taint
  t.protected, t.noCombat, t.enforce = copy(Data.protected), copy(Data.noCombat), true
  w.callGate = function(name, signature, args)
    refuseSecret(w, name, signature, args)
    return M.guardCall(w, name)
  end
end

return M

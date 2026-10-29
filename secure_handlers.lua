-- The SecureHandler API: Execute, SetFrameRef, WrapScript and UnwrapScript as frame methods and as SecureHandler* globals,
-- with the checks the client makes on their arguments. The restricted environment is secure_env.lua, the handle methods
-- secure_handle.lua, the template scripts secure_scripts.lua, the script wrappers secure_wrap.lua.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/securehandlers.lua (lines cited per function); the code
-- is the kit's.
local Callsite = require("ui.callsite")
local Scripts = require("secure_scripts")
local SecureEnv = require("secure_env")
local Taint = require("taint")
local Wrap = require("secure_wrap")

require("secure_handle")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, error, pairs, setmetatable = type, error, pairs, setmetatable

local FRAMEXML = { gate = "framexml", flavors = {} }
local COMBAT_ERROR = "Cannot use SecureHandlers API during combat"
local FORBIDDEN_ERROR = "Cannot use SecureHandlers API on forbidden frames"

local function inCombat(w)
  return w.mock ~= nil and w.mock.combat == true
end

local function fail(message)
  error(message, Callsite.level())
end

local function isFrame(w, value)
  local st = type(value) == "table" and w.ui.state[value]
  return st and st.plan.isFrame == true or false
end

local function isForbidden(w, frame)
  return w.ui.state[frame].forbidden == true
end

local function isExplicit(w, frame)
  local _, explicit = w.taint.isProtected(w, frame)
  return explicit
end

-- API ----------------------------------------------------------------------------------------------------------

local function checkFrame(w, frame, message)
  if not isFrame(w, frame) then
    fail(message)
  elseif isForbidden(w, frame) then
    fail(FORBIDDEN_ERROR)
  end
end

-- source: `:430-441` (API_OnAttributeChanged) each call's second half runs as the API frame's OnAttributeChanged script:
-- secure whoever calls, refusing every caller in combat. An error it raises goes to the error handler and the call returns
-- on (assumed: a script's error never reaches SetAttribute's caller; UnwrapScript's result check `:665-674` relies on it).
-- True when fn ran without an error.
local function apiScript(w, fn)
  return Taint.secure(w, w.try, w, function()
    if inCombat(w) then
      error(COMBAT_ERROR, 0)
    end
    fn()
  end)[1]
end

-- source: `:680-700` (SecureHandlerExecute) and `:444-459` (_execute): runs body as secure execution against a header, for
-- a tainted caller too; an error in the snippet goes to the error handler.
function M.execute(w, frame, body)
  checkFrame(w, frame, "Invalid header frame")
  if not isExplicit(w, frame) then
    fail("Header frame must be explicitly protected")
  elseif type(body) ~= "string" then
    fail("Invalid body")
  end
  apiScript(w, function()
    SecureEnv.call(w, frame, frame, "self", body)
  end)
end

-- source: `:702-729` (SecureHandlerSetFrameRef) and `:558-585` (_frame-<label>).
function M.setFrameRef(w, frame, label, refFrame)
  checkFrame(w, frame, "Invalid frame")
  if type(label) ~= "string" then
    fail("Invalid body")
  end
  checkFrame(w, refFrame, "Invalid reference frame")
  apiScript(w, function()
    frame:SetAttribute("frameref-" .. label, SecureEnv.handle(w, refFrame))
  end)
end

-- source: `:602-644` (SecureHandlerWrapScript) and `:461-518` (_wrap): the wrapper becomes the frame's script (so a later
-- SetScript replaces it) and keeps the handler it replaced; the script checks are the API frame's (apiScript).
function M.wrapScript(w, frame, script, header, preBody, postBody)
  checkFrame(w, frame, "Invalid frame")
  if type(script) ~= "string" then
    fail("Invalid script id")
  end
  checkFrame(w, header, "Invalid header frame")
  if not isExplicit(w, header) then
    fail("Header frame must be explicitly protected")
  elseif type(preBody) ~= "string" then
    fail("Invalid pre-handler body")
  elseif postBody ~= nil and type(postBody) ~= "string" then
    fail("Invalid post-handler body")
  end
  apiScript(w, function()
    local wrapper = Wrap.wrappers[script]
    if not frame:HasScript(script) then
      error("Frame does not support script '" .. script .. "'", 0)
    elseif not wrapper then
      error("Unsupported script type '" .. script .. "'", 0)
    end
    local info = { header = header, preBody = preBody, postBody = postBody, original = frame:GetScript(script) }
    local function wrap(self, ...)
      return wrapper(w, self, info, ...)
    end
    SecureEnv.state(w).wraps[wrap] = info
    frame:SetScript(script, wrap)
  end)
end

-- source: `:646-678` (SecureHandlerUnwrapScript), `:520-556` (_unwrap) and `:238-253` (RemoveWrapper): restores the
-- handler the wrap replaced and returns the header and bodies; a script that is not wrapped is left as it is and returns
-- three nils (`:667-676` reads them from the empty result slots). "Unable to retrieve unwrap results" only when the API
-- frame's half raised (apiScript).
function M.unwrapScript(w, frame, script)
  checkFrame(w, frame, "Invalid frame")
  if type(script) ~= "string" then
    fail("Invalid script id")
  end
  local info
  local ran = apiScript(w, function()
    if not frame:HasScript(script) then
      error("Frame does not support script '" .. script .. "'", 0)
    end
    info = SecureEnv.state(w).wraps[frame:GetScript(script)]
    if info then
      frame:SetScript(script, info.original)
    end
  end)
  if not ran then
    fail("Unable to retrieve unwrap results")
  elseif info then
    return info.header, info.preBody, info.postBody
  end
  return nil, nil, nil
end

-- The methods the handler templates put on their frames (SecureHandler_OnLoad): fn(w, self, ...).
M.methods = {
  Execute = function(w, self, body)
    return M.execute(w, self, body)
  end,
  SetFrameRef = function(w, self, label, frame)
    return M.setFrameRef(w, self, label, frame)
  end,
  WrapScript = function(w, self, frame, script, preBody, postBody)
    return M.wrapScript(w, frame, script, self, preBody, postBody)
  end,
  UnwrapScript = function(w, _, frame, script)
    return M.unwrapScript(w, frame, script)
  end,
}

function M.install(w)
  SecureEnv.install(w)
  SecureEnv.state(w).wraps = setmetatable({}, { __mode = "k" })
  local function define(name, fn)
    w:install(name, function(...)
      return fn(w, ...)
    end, FRAMEXML)
  end
  define("SecureHandlerExecute", M.execute)
  define("SecureHandlerSetFrameRef", M.setFrameRef)
  define("SecureHandlerWrapScript", M.wrapScript)
  define("SecureHandlerUnwrapScript", M.unwrapScript)
  define("SecureHandler_OnSimpleEvent", Scripts.onSimpleEvent)
  define("SecureHandler_OnClick", Scripts.onClick)
  define("SecureHandler_OnMouseUpDown", Scripts.onMouseUpDown)
  define("SecureHandler_OnMouseWheel", Scripts.onMouseWheel)
  define("SecureHandler_OnDragEvent", Scripts.onDragEvent)
  define("SecureHandler_StateOnAttributeChanged", Scripts.onStateChanged)
  define("SecureHandler_AttributeOnAttributeChanged", Scripts.onAttributeChanged)
  define("SecureHandler_OnLoad", function(world, frame)
    for name, fn in pairs(M.methods) do
      frame[name] = function(self, ...)
        return fn(world, self, ...)
      end
    end
  end)
end

return M

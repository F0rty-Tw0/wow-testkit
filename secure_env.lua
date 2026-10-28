-- The restricted environment snippets run in: a whitelist of names and a handle for each frame (the table `self` and
-- `control` are), one persistent environment per header frame, and the one way a snippet runs (SecureEnv.call, what
-- CallRestrictedClosure does). The handle methods live in secure_handle.lua, which fills M.handleMethods.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/restrictedenvironment.lua:24-78 (the names) and
-- restrictedexecution.lua:444-482 (the call). The names are facts; the code is the kit's.
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local rawget, pairs, ipairs, type, tostring, select, pcall, error = rawget, pairs, ipairs, type, tostring, select, pcall, error
local setmetatable, loadstring, setfenv, unpack, next = setmetatable, loadstring, setfenv, unpack, next
local remove = table.remove

M.handleMethods = {}

-- Names copied from the global environment when a header first runs a snippet; one the flavour lacks stays nil.
local GLOBAL_NAMES = [[
  format gmatch gsub strbyte strchar strcmputf8i strconcat strfind strjoin strlen strlenutf8 strlower strmatch strrep strrev
  strsplit strsub strtrim strupper abs acos asin atan atan2 ceil cos deg exp floor frexp ldexp log log10 max min mod rad random
  sin tan
]]
-- Names that call the global function of that name (or a dotted one) when the snippet does, so a function a test stubs or
-- a flavour lacks is looked up at the call: the macro-conditional queries, the bar and binding queries, the player queries.
local FORWARDED = [[
  SecureCmdOptionParse GetShapeshiftForm IsStealthed UnitExists UnitIsDead UnitIsGhost UnitPlayerOrPetInParty
  UnitPlayerOrPetInRaid IsRightAltKeyDown IsLeftAltKeyDown IsAltKeyDown IsRightControlKeyDown IsLeftControlKeyDown
  IsControlKeyDown IsLeftShiftKeyDown IsRightShiftKeyDown IsShiftKeyDown IsModifierKeyDown IsModifiedClick
  GetMouseButtonClicked IsMounted IsSwimming IsSubmerged IsFlying IsFlyableArea IsAdvancedFlyableArea IsDrivableArea
  IsIndoors IsOutdoors CanExitVehicle FindSpellBookSlotBySpellID GetBindingKey GetMultiCastTotemSpells GetActionInfo
  UnitTargetsVehicleInRaidUI print IsGamePadEnabled GetGamePadState GetTransmogOutfitIndex UnitHasVehicleUI
  GetActionBarPage=C_ActionBar.GetActionBarPage GetBonusBarIndex=C_ActionBar.GetBonusBarIndex
  GetBonusBarOffset=C_ActionBar.GetBonusBarOffset GetOverrideBarIndex=C_ActionBar.GetOverrideBarIndex
  GetTempShapeshiftBarIndex=C_ActionBar.GetTempShapeshiftBarIndex GetVehicleBarIndex=C_ActionBar.GetVehicleBarIndex
  HasAction=C_ActionBar.HasAction HasBonusActionBar=C_ActionBar.HasBonusActionBar
  HasExtraActionBar=C_ActionBar.HasExtraActionBar HasOverrideActionBar=C_ActionBar.HasOverrideActionBar
  HasTempShapeshiftActionBar=C_ActionBar.HasTempShapeshiftActionBar HasVehicleActionBar=C_ActionBar.HasVehicleActionBar
  IsHarmfulItem=C_Item.IsHarmfulItem IsHelpfulItem=C_Item.IsHelpfulItem IsSpellHarmful=C_Spell.IsSpellHarmful
  IsSpellHelpful=C_Spell.IsSpellHelpful IsPressHoldReleaseSpell=C_Spell.IsPressHoldReleaseSpell
]]
-- Forwarded names whose first argument is a frame handle (the driver and unit-watch calls).
local HANDLE_FIRST = [[RegisterStateDriver UnregisterStateDriver RegisterAttributeDriver UnregisterAttributeDriver
  RegisterUnitWatch UnregisterUnitWatch UnitWatchRegistered]]

local function weakKeys()
  return setmetatable({}, { __mode = "k" })
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- The value at a dotted global path ("C_Item.IsHarmfulItem"), or nil.
function M.resolve(path)
  local value = _G
  for part in path:gmatch("[^.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

local function meta(w)
  local cache = {}
  return {
    __index = function(_, name)
      local fn = cache[name]
      local impl = M.handleMethods[name]
      if not fn and impl then
        fn = function(self, ...)
          return impl(w, self, ...)
        end
        cache[name] = fn
      end
      return fn
    end,
    __newindex = function() end,
    __metatable = false,
  }
end

function M.state(w)
  local s = w.secure
  if not s then
    s = { handles = weakKeys(), frames = weakKeys(), envs = weakKeys() }
    s.meta = meta(w)
    w.secure = s
  end
  return s
end

-- The handle for frame (the same table each time).
function M.handle(w, frame)
  local s = M.state(w)
  local handle = s.handles[frame]
  if not handle then
    handle = setmetatable({}, s.meta)
    s.handles[frame], s.frames[handle] = handle, frame
  end
  return handle
end

-- The frame a handle stands for, or nil when value is not a handle.
function M.frameOf(w, value)
  return type(value) == "table" and M.state(w).frames[value] or nil
end

-- Replaces each handle among the arguments with its frame.
function M.toFrames(w, ...)
  local args = pack(...)
  for i = 1, args.n do
    args[i] = M.frameOf(w, args[i]) or args[i]
  end
  return unpack(args, 1, args.n)
end

local function wipe(tbl)
  for k in pairs(tbl) do
    tbl[k] = nil
  end
  return tbl
end

local function copyTable(tbl)
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = type(v) == "table" and copyTable(v) or v
  end
  return out
end

local function forward(w, path, withHandle)
  return function(...)
    local fn = M.resolve(path)
    if not fn then
      return nil
    end
    return fn(withHandle and M.toFrames(w, ...) or ...)
  end
end

-- The names every header's environment sees (built once per world, from the globals of that time).
local function baseEnv(w, s)
  if s.base then
    return s.base
  end
  local base = { math = copyTable(math), string = copyTable(string), select = select, tonumber = tonumber, tostring = tostring }
  base.rawtype = type
  for name in GLOBAL_NAMES:gmatch("%S+") do
    base[name] = rawget(_G, name)
  end
  local handleFirst = {}
  for name in HANDLE_FIRST:gmatch("%S+") do
    handleFirst[name] = true
  end
  for entry in (FORWARDED .. " " .. HANDLE_FIRST):gmatch("%S+") do
    local name, path = entry:match("^([^=]+)=(.+)$")
    name = name or entry
    base[name] = forward(w, path or name, handleFirst[name])
  end
  base.newtable = function()
    return {}
  end
  base.copytable = copyTable
  base.pairs, base.ipairs, base.next, base.unpack, base.type, base.wipe = pairs, ipairs, next, unpack, type, wipe
  base.tinsert, base.tremove, base.rtgsub = table.insert, remove, string.gsub
  base.table =
    { maxn = table.maxn, insert = table.insert, remove = remove, sort = table.sort, concat = table.concat, wipe = wipe, new = base.newtable }
  base.PlayerCanAttack = function(unit)
    return forward(w, "UnitCanAttack")("player", unit)
  end
  base.PlayerCanAssist = function(unit)
    return forward(w, "UnitCanAssist")("player", unit)
  end
  base.PlayerInCombat = function()
    return forward(w, "UnitAffectingCombat")("player") or forward(w, "UnitAffectingCombat")("pet")
  end
  base.PlayerIsChanneling = function()
    return forward(w, "UnitChannelInfo")("player") ~= nil
  end
  s.base = base
  return base
end

-- A header's own environment: the base names, plus whatever its snippets assigned (they persist between runs).
local function envOf(w, header)
  local s = M.state(w)
  local env = s.envs[header]
  if not env then
    env = setmetatable({}, { __index = baseEnv(w, s), __metatable = false })
    s.envs[header] = env
  end
  return env
end

-- source: restrictedexecution.lua:58-70 the body may contain neither the word function nor a brace; the signature is
-- names, commas and an optional trailing ... .
local function build(signature, body, env)
  if body:match("function") or signature:match("function") then
    error("The function keyword is not permitted", 0)
  elseif body:match("[{}]") then
    error("Direct table creation is not permitted", 0)
  elseif not signature:match("^[a-zA-Z_0-9, ]*[.]*$") then
    error("Signature contains invalid characters (" .. signature .. ")", 0)
  end
  local def, err = loadstring("return function (" .. signature .. ") " .. body .. "\nend", "=(snippet)")
  if not def then
    error(err, 0)
  end
  setfenv(def, {})
  local closure = def()
  setfenv(closure, env)
  return closure
end

-- source: restrictedexecution.lua:444-482 (CallRestrictedClosure, with the header's environment and `control` set to its
-- handle): runs body as function(signature) with self = owner's handle, and returns what it returns. Raises when owner
-- is forbidden, when the body does not compile, when the caller is tainted ("Cannot call restricted closure from insecure
-- code", `:469-470`), and "Call failed: <message>" when the body errors.
function M.call(w, owner, header, signature, body, ...)
  if w.ui.state[owner].forbidden then
    error("Cannot use SecureHandlers API on forbidden frames", 0)
  end
  local env = envOf(w, header)
  local closure = build(tostring(signature), body, env)
  if Taint.current(w) then
    error("Cannot call restricted closure from insecure code", 0)
  end
  local outer = rawget(env, "control")
  env.control = M.handle(w, header)
  local results = pack(pcall(closure, M.handle(w, owner), ...))
  env.control = outer
  if not results[1] then
    error("Call failed: " .. tostring(results[2]), 0)
  end
  return unpack(results, 2, results.n)
end

-- Runs body on frame (self = its handle, control = its handle) as secure execution, whoever asks; an error goes to the
-- error handler and the call returns on. Returns the packed result ({ n, ok, ... }).
function M.run(w, frame, body, ...)
  return Taint.secure(w, function(...)
    return w:try(M.call, w, frame, frame, "self,...", body, ...)
  end, ...)
end

return M

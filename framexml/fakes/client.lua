-- The client extract (w.client) as the world's data: its GlobalStrings over the kit's test values, its glyph tables as the
-- text measure, and its atlas rows behind C_Texture.GetAtlasInfo. A no-op without an extract, so a world built with no
-- client is the kit's own.
local M = {}

local Client = require("client")
local Measure = require("ui.measure")

local STRING_GATE = { gate = "none" }
local API_GATE = { gate = "api" }

local function installStrings(w)
  for name, value in pairs(Client.strings(w.client) or {}) do
    w:install(name, value, STRING_GATE)
  end
end

local function atlasInfo(extract, name)
  local row = type(name) == "string" and Client.atlas(extract, name)
  if not row then
    return nil
  end
  return {
    width = row.width,
    height = row.height,
    leftTexCoord = row.left,
    rightTexCoord = row.right,
    topTexCoord = row.top,
    bottomTexCoord = row.bottom,
    file = row.file,
    tilesHorizontally = false,
    tilesVertically = false,
  }
end

-- Whether every key target and fields share has the same value in both; strict: also every key of target is in fields.
local function agrees(target, fields, strict)
  for key, value in pairs(fields) do
    local kit = rawget(target, key)
    if kit ~= nil and kit ~= value then
      return false
    end
  end
  if strict then
    for key in pairs(target) do
      if fields[key] == nil then
        return false
      end
    end
  end
  return true
end

local function copy(fields)
  local out = {}
  for key, value in pairs(fields) do
    out[key] = value
  end
  return out
end

-- Overlays root (the Enum or Constants table the world installed) with the extract's tables. A table the kit lacks is
-- copied in. A kit table that agrees with the extract on every shared key gets only its missing fields. A kit table that
-- disagrees on any value (a renumbered member, a Meta MaxValue) is replaced by a copy of the extract's: the extract is
-- that build's own docs, and a per-field mix gave two members one value (VasTransactionPurchaseResult) and Meta rows
-- that stop short of the added members (ChatChannelTypeMeta). strict (Enum): a member only the kit has disagrees too,
-- since a renamed member keeps its value (forever ForeverExperiencePreset Modern = 1 became Enhanced = 1); Constants
-- keep their kit-only members (row G40). Non-table entries and non-table kit values are skipped.
local function overlay(w, root, tables, strict)
  for name, fields in pairs(tables) do
    local target = rawget(root, name)
    if type(fields) == "table" and target == nil then
      w:rawWrite(root, name, copy(fields))
    elseif type(fields) == "table" and type(target) == "table" then
      if agrees(target, fields, strict) then
        for key, value in pairs(fields) do
          if rawget(target, key) == nil then
            target[key] = value
          end
        end
      else
        w:rawWrite(root, name, copy(fields))
      end
    end
  end
end

local function namespaceOf(name)
  return name:match("^(.+)%.[^.]+$")
end

-- Every namespace the flavor's own data has a function in.
local function flavorNamespaces(w)
  local namespaces = {}
  for _, names in ipairs({ w.manifest.functions, w.globals.api }) do
    for name in pairs(names) do
      local namespace = namespaceOf(name)
      if namespace then
        namespaces[namespace] = true
      end
    end
  end
  return namespaces
end

-- Row G75: a documented function the kit's data lacks becomes a signature stub, as installBase makes for its own.
-- Only in a namespace the flavor's data has: a classic client's docs list systems it does not ship (C_AuctionHouse on
-- Classic Era). Globals and secure-only functions are left out for the same reason.
-- They are kept in w.clientFunctions, so w:stub and the kit's api-gated installs treat them as API functions.
local function installFunctions(w, functions)
  local namespaces = flavorNamespaces(w)
  w.clientFunctions = {}
  for name, signature in pairs(functions) do
    local namespace = namespaceOf(name)
    local known = w.manifest.functions[name] or w.globals.api[name]
    if namespace and namespaces[namespace] and not known and type(signature) == "table" and not signature.secureOnly then
      w.clientFunctions[name] = signature
      w:installStub(name, signature)
    end
  end
end

-- source: the client build's own API docs (Blizzard_APIDocumentationGenerated in the extract) list the enums and
-- constants its UI code reads, the events it registers (row G57) and the functions it calls (row G75); the kit's
-- pinned api/<flavor> data can be older than the extract.
local function installApi(w)
  local api = Client.api(w.client)
  if not api then
    return
  end
  w.clientEvents = api.events -- read by World:knowsEvent
  installFunctions(w, api.functions)
  for root, tables in pairs({ Enum = api.enums, Constants = api.constants }) do
    local installed = rawget(_G, root) -- world.lua installBase sets both
    if type(installed) == "table" then
      overlay(w, installed, tables, root == "Enum")
    end
  end
end

function M.install(w)
  if not w.client then
    return
  end
  installStrings(w)
  installApi(w)
  Measure.useGlyphs(w, Client.glyphs(w.client))
  w:install("C_Texture.GetAtlasInfo", function(name)
    return atlasInfo(w.client, name)
  end, API_GATE)
end

return M

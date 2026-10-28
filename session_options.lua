-- Session options: the flavor "auto" stands for, the screen presets, and the one check of what a reload may change
-- (flavor, size or screen, keepSaved). Session.reload runs it; the hosts only forward a reload request to it.
local M = {}

local Flavors = require("tools.flavors")
local Screen = require("ui.screen")
local Toc = require("toc")
local fs = require("fs")

local DEFAULT_FLAVOR = "retail"
local MIN_WIDTH, MIN_HEIGHT = 320, 240
local MAX_WIDTH, MAX_HEIGHT = 7680, 4320
local FLAVOR_ERROR = 'reload: flavor must be "auto" or one of ' .. table.concat(Flavors.list, ", ")
local SIZE_ERROR = "reload: size must be 1080p, 1440p, 4k or { width, height } in whole pixels within 320x240 to 7680x4320"
local SCREEN_ERROR = "reload: screen must be { width, height, ... } in whole pixels within 320x240 to 7680x4320"

M.PRESETS = { ["1080p"] = { 1920, 1080 }, ["1440p"] = { 2560, 1440 }, ["4k"] = { 3840, 2160 } }

-- Toc.declared for the TOC the client reads on flavor; nil when it cannot be read.
local function declaredOn(root, name, flavor)
  local text = fs.readFile(Toc.select(root, name, flavor))
  if not text then
    return nil
  end
  return Toc.declared(Toc.parse(text).meta, flavor)
end

-- The flavor "auto" means for the addon in addonDir: the first flavor (Flavors.list order) its TOC declares as
-- current ("load"), else the first it declares outdated or ahead, else retail.
function M.autoFlavor(addonDir)
  local name = Toc.addonName(addonDir)
  if not name then
    return DEFAULT_FLAVOR
  end
  local near
  for _, flavor in ipairs(Flavors.list) do
    local declared = declaredOn(addonDir, name, flavor)
    if declared == "load" then
      return flavor
    end
    local usable = declared == "outdated" or declared == "ahead"
    if usable and not near then
      near = flavor
    end
  end
  return near or DEFAULT_FLAVOR
end

-- The flavor a session with these options opens on: nil and "auto" are autoFlavor's answer.
function M.flavorOf(opts)
  if opts.flavor == nil or opts.flavor == "auto" then
    return M.autoFlavor(opts.addonDir)
  end
  return opts.flavor
end

local function checkFlavor(flavor)
  local known = flavor == "auto"
  for _, name in ipairs(Flavors.list) do
    known = known or flavor == name
  end
  if not known then
    error(FLAVOR_ERROR, 0)
  end
end

local function inRange(value, low, high)
  return type(value) == "number" and value % 1 == 0 and value >= low and value <= high
end

-- True when t is a table whose width and height are whole pixels within 320x240 to 7680x4320.
local function fits(t)
  return type(t) == "table" and inRange(t.width, MIN_WIDTH, MAX_WIDTH) and inRange(t.height, MIN_HEIGHT, MAX_HEIGHT)
end

-- width, height of a size: a preset name or { width, height } in range.
local function sizeOf(size)
  local preset = type(size) == "string" and M.PRESETS[size]
  if preset then
    return preset[1], preset[2]
  end
  if not fits(size) then
    error(SIZE_ERROR, 0)
  end
  return size.width, size.height
end

-- screen with its width and height replaced; the UI scale settings stay.
local function resized(screen, width, height)
  local out = {}
  for key, value in pairs(screen or {}) do
    out[key] = value
  end
  out.width, out.height = width, height
  return out
end

-- The Blizzard UI layer a reload asks for: on is the layer the session first opened with (its targets), else true.
-- blizzardLayer keeps that first layer across reloads that turn it off.
local function toggleLayer(out, opts, on)
  out.blizzardLayer = opts.blizzardLayer or opts.blizzardUi or nil
  out.blizzardUi = on and (out.blizzardLayer or true)
end

-- The options a reload of a session opened with opts uses: over's flavor ("auto" or a name in Flavors.list) and size
-- (a preset name or { width, height }) or screen, and blizzardUi (true or false: the layer on or off; on needs
-- opts.extract, so the layer never falls back to Client.find's extract); over's other fields are ignored, so the addon
-- folder, extract and session folder stay the process's. Raises, naming the field, on anything a world would refuse, so
-- a caller can run it before it touches the current world.
function M.reopen(opts, over)
  if over.keepSaved ~= nil and type(over.keepSaved) ~= "boolean" then
    error("reload: keepSaved must be true or false", 0)
  elseif over.blizzardUi ~= nil and type(over.blizzardUi) ~= "boolean" then
    error("reload: blizzardUi must be true or false", 0)
  elseif over.blizzardUi and not opts.extract then
    error("reload: blizzardUi needs a session started with --extract", 0)
  end
  if over.size ~= nil and over.screen ~= nil then
    error("reload: give size or screen, not both", 0)
  end
  local out = {}
  for key, value in pairs(opts) do
    out[key] = value
  end
  if over.flavor ~= nil then
    checkFlavor(over.flavor)
    out.flavor = over.flavor
  end
  if over.screen ~= nil then
    local fitting = fits(over.screen)
    if not fitting then
      error(SCREEN_ERROR, 0)
    end
    out.screen = over.screen
  end
  if over.size ~= nil then
    out.screen = resized(opts.screen, sizeOf(over.size))
  end
  if over.blizzardUi ~= nil then
    toggleLayer(out, opts, over.blizzardUi)
  end
  Screen.normalize(out.screen)
  return out
end

return M

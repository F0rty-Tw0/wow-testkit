-- Nameplates: a plate frame for every actor the nameplate CVars allow in range of the origin. Each plate is a
-- NamePlate<N> frame under WorldFrame holding a kit stand-in UnitFrame, and binds the actor to a nameplate<N> token, so
-- every Unit* API answers for it. Plates sync on the spawn, despawn, moved and cvar hooks and follow the actor's health.
-- c.plates maps token -> { frame, token, index, actor, forbidden }; c.platePool lists the frames waiting for reuse.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local Layout = require("ui.layout")
local State = require("game.state")
local define = State.define

local unpack = unpack

-- source: assumed (row C14) the default plate size; the page names no value.
local PLATE_WIDTH, PLATE_HEIGHT = 110, 45
-- source: confirmed (row C14) nameplateShowEnemies and nameplateMaxDistance defaults; assumed nameplateShowFriends.
local CVAR_DEFAULTS = { nameplateshowenemies = "1", nameplateshowfriends = "0", nameplatemaxdistance = "60.000000" }
local DEFAULT_DISTANCE = 60
local PLAYER = "player"
-- The stand-in ground plane: the camera looks along +y from five units behind the origin.
local CAMERA_BACK, FOV_SCALE, HORIZON, GROUND_DROP = 5, 0.9, 0.55, 2

local function ordered(c)
  local list = {}
  for _, plate in pairs(c.plates) do
    list[#list + 1] = plate
  end
  table.sort(list, function(a, b)
    return a.index < b.index
  end)
  return list
end

local function plateOf(c, actor)
  for _, plate in pairs(c.plates) do
    if plate.actor == actor then
      return plate
    end
  end
end

-- Stand-in ground projection in WorldFrame UI units; nil when the actor is behind the camera.
function M.project(w, actor)
  local distance = actor.pos.y + CAMERA_BACK
  if distance <= 0 then
    return nil
  end
  local world = Layout.rect(w, _G.WorldFrame)
  local scale = FOV_SCALE * world.height
  return world.width / 2 + scale * actor.pos.x / distance, HORIZON * world.height - scale * GROUND_DROP / distance
end

-- nil when the actor gets no plate, else whether its plate is forbidden (a friend inside an instance).
local function forbiddenFor(w, actor)
  local cvars = w.mock.cvars
  -- source: assumed (no row) a dead unit has no plate; a revive brings it back.
  if actor.isDead then
    return nil
  end
  if actor.isEnemy then
    if cvars.nameplateshowenemies ~= "1" then
      return nil
    end
  elseif cvars.nameplateshowfriends ~= "1" then
    return nil
  end
  local pos = actor.pos
  if math.sqrt(pos.x * pos.x + pos.y * pos.y) > (tonumber(cvars.nameplatemaxdistance) or DEFAULT_DISTANCE) then
    return nil
  end
  return not actor.isEnemy and w.mock.instance.type ~= "none"
end

local function newFrame(w, c)
  c.plateCount = c.plateCount + 1
  local frame = w.ui.create("Frame", "NamePlate" .. c.plateCount, _G.WorldFrame)
  frame:SetSize(PLATE_WIDTH, PLATE_HEIGHT)
  local unitFrame = w.ui.create("Frame", nil, frame)
  unitFrame.name = unitFrame:CreateFontString()
  unitFrame.healthBar = w.ui.create("StatusBar", nil, unitFrame)
  frame.UnitFrame = unitFrame
  return frame
end

local function place(w, plate)
  local x, y = M.project(w, plate.actor)
  if not x then
    plate.frame:Hide()
    return
  end
  plate.frame:ClearAllPoints()
  plate.frame:SetPoint("BOTTOM", _G.WorldFrame, "BOTTOMLEFT", x, y)
  plate.frame:Show()
end

local function updateHealth(plate)
  local bar, actor = plate.frame.UnitFrame.healthBar, plate.actor
  bar:SetMinMaxValues(0, actor.healthMax)
  bar:SetValue(actor.health)
end

local function lowestFreeIndex(c)
  local index = 1
  while c.plates["nameplate" .. index] do
    index = index + 1
  end
  return index
end

-- source: confirmed (row C13) NAME_PLATE_CREATED fires for a frame the driver has not seen; assumed it fires only when
-- no pooled frame is free. A forbidden plate fires the FORBIDDEN_ twin of each event (assumed).
local function add(w, c, actor, forbidden)
  local prefix = forbidden and "FORBIDDEN_" or ""
  local frame = table.remove(c.platePool)
  if not frame then
    frame = newFrame(w, c)
    Combat.fire(w, prefix .. "NAME_PLATE_CREATED", frame)
  end
  local index = lowestFreeIndex(c)
  local token = "nameplate" .. index
  local plate = { frame = frame, token = token, index = index, actor = actor, forbidden = forbidden }
  c.plates[token] = plate
  Actors.bind(w, actor, token)
  local unitFrame = frame.UnitFrame
  frame.namePlateUnitToken = token
  unitFrame.unit, unitFrame.displayedUnit = token, token
  unitFrame.name:SetText(actor.name)
  updateHealth(plate)
  place(w, plate)
  Combat.fire(w, prefix .. "NAME_PLATE_UNIT_ADDED", token)
end

-- source: confirmed (row C13) the token still maps to its plate while REMOVED is delivered.
local function remove(w, c, plate)
  if plate.removing then
    return
  end
  plate.removing = true
  Combat.fire(w, (plate.forbidden and "FORBIDDEN_" or "") .. "NAME_PLATE_UNIT_REMOVED", plate.token)
  Actors.unbind(w, plate.token)
  c.plates[plate.token] = nil
  local frame = plate.frame
  frame.namePlateUnitToken = nil
  frame.UnitFrame.unit, frame.UnitFrame.displayedUnit = nil, nil
  frame:Hide()
  c.platePool[#c.platePool + 1] = frame
end

-- Brings the plates in line with the actors, the CVars and the instance: removals first, then additions in spawn order,
-- then every plate's place.
function M.sync(w)
  local c = w.combat
  local player = w.unitState.byToken[PLAYER]
  local wanted = {}
  for _, guid in ipairs(c.order) do
    local actor = c.actors[guid]
    if actor ~= player then
      wanted[actor] = forbiddenFor(w, actor)
    end
  end
  for _, plate in ipairs(ordered(c)) do
    if wanted[plate.actor] == nil or wanted[plate.actor] ~= plate.forbidden then
      remove(w, c, plate)
    end
  end
  for _, guid in ipairs({ unpack(c.order) }) do
    local actor = c.actors[guid]
    if actor and wanted[actor] ~= nil and not plateOf(c, actor) then
      add(w, c, actor, wanted[actor])
    end
  end
  for _, plate in ipairs(ordered(c)) do
    if not plate.removing then
      place(w, plate)
    end
  end
end

function M.install(w)
  local c = w.combat
  c.plates, c.platePool, c.plateCount = {}, {}, 0
  State.fill(w.mock.cvars, CVAR_DEFAULTS)
  local function sync()
    M.sync(w)
  end
  Combat.listen(w, "spawn", sync)
  Combat.listen(w, "moved", sync)
  Combat.listen(w, "cvar", sync)
  Combat.listen(w, "death", sync)
  Combat.listen(w, "flags", sync)
  -- The despawn hook runs before the actor's tokens are unbound, so its plate still resolves while REMOVED is delivered.
  Combat.listen(w, "despawn", function(actor)
    local plate = plateOf(c, actor)
    if plate then
      remove(w, c, plate)
    end
  end)
  local function follow(actor)
    local plate = plateOf(c, actor)
    if plate then
      updateHealth(plate)
    end
  end
  Combat.listen(w, "health", follow)
  Combat.listen(w, "healthmax", follow)
  -- source: confirmed (row C13) includeForbidden also returns the protected friendly plates of an instance.
  define(w, "C_NamePlate.GetNamePlateForUnit", function(unit, includeForbidden)
    local plate = type(unit) == "string" and c.plates[unit:lower()] or nil
    return plate and (includeForbidden or not plate.forbidden) and plate.frame or nil
  end)
  define(w, "C_NamePlate.GetNamePlates", function(includeForbidden)
    local frames = {}
    for _, plate in ipairs(ordered(c)) do
      if includeForbidden or not plate.forbidden then
        frames[#frames + 1] = plate.frame
      end
    end
    return frames
  end)
  define(w, "C_NamePlate.GetNamePlateSize", function()
    return PLATE_WIDTH, PLATE_HEIGHT
  end)
  sync() -- actors adopted from fixtures before the install
end

return M

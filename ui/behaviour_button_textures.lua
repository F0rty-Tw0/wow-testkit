-- Hand-written button state textures: the region that fills each role of a Button (normal, pushed, highlight,
-- disabled) or CheckButton (checked, disabledChecked). A role region has st.role and st.btn.tex[role]; one the button
-- made itself also has st.roleOwned. Registers through Typed.add, so M.methods stays empty. Methods are
-- fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local BehaviourTexture = require("ui.behaviour_texture")
local Slot = require("ui.role_slot")
local State = require("ui.button_state")
local Typed = require("ui.typed")

M.methods = {}

local DEFAULT_HIGHLIGHT_BLEND = "ADD"

-- source: assumed (W19) normal, pushed and disabled textures draw on ARTWORK, the highlight on HIGHLIGHT. The checked
-- roles keep the layer their region already has.
local ROLE_LAYER = { normal = "ARTWORK", pushed = "ARTWORK", highlight = "HIGHLIGHT", disabled = "ARTWORK" }

local KEYS = { mark = "role", owned = "roleOwned" }

local function release(w, obj, st, role)
  Slot.release(w, obj, State.write(st).tex, role, KEYS)
end

-- source: confirmed (W18) a texture object is re-parented to the button; assumed (W18) a path or atlas retextures the
-- region that already fills the role (adopted or made by the button), else makes a region of the button that fills it,
-- and so does an object with no anchors of its own (blizzard_sharedxml/modelscenetemplates.xml:25 draws a state texture
-- with none).
local function regionFor(w, obj, st, role, asset)
  local existing = Slot.held(w, State.read(st).tex, role, obj)
  if Slot.isTexture(w, asset) then
    if existing ~= asset then
      release(w, obj, st, role)
      asset:SetParent(obj)
      if ROLE_LAYER[role] then
        asset:SetDrawLayer(ROLE_LAYER[role])
      end
      if asset:GetNumPoints() == 0 then
        asset:SetAllPoints()
      end
      Slot.claim(w, State.write(st).tex, role, asset, false, KEYS)
    end

    return asset
  end
  if existing then
    return existing
  end
  local region = obj:CreateTexture(nil, ROLE_LAYER[role])
  region:SetAllPoints()
  Slot.claim(w, State.write(st).tex, role, region, true, KEYS)

  return region
end

-- source: assumed (W19) the highlight blend is ADD unless one is given (or the texture already has its own).
local function setHighlightBlend(w, region, blend)
  local hasOwn = BehaviourTexture.read(w.ui.state[region]).blend ~= nil
  if blend then
    region:SetBlendMode(blend)
  elseif not hasOwn then
    region:SetBlendMode(DEFAULT_HIGHLIGHT_BLEND)
  end
end

-- A path, file id or atlas name onto a region the button made.
local function setSource(region, asset, isAtlas)
  if isAtlas then
    region:SetAtlas(asset)
  else
    region:SetTexture(asset)
  end
end

local function setRoleSource(role, isAtlas)
  return function(w, obj, st, asset, blend)
    if asset == nil then
      release(w, obj, st, role)

      return
    end
    local region = regionFor(w, obj, st, role, asset)
    if not Slot.isTexture(w, asset) then
      setSource(region, asset, isAtlas)
    end
    if role == "highlight" then
      setHighlightBlend(w, region, blend)
    end
  end
end

local function clearRole(role)
  return function(w, obj, st)
    release(w, obj, st, role)
  end
end

local function getRole(role)
  return function(w, obj, st)
    return Slot.held(w, State.read(st).tex, role, obj)
  end
end

local STATE_ROLES = { Normal = "normal", Pushed = "pushed", Highlight = "highlight", Disabled = "disabled" }
for label, role in pairs(STATE_ROLES) do
  Typed.add("Set" .. label .. "Texture", "button", setRoleSource(role, false))
  Typed.add("Set" .. label .. "Atlas", "button", setRoleSource(role, true))
  Typed.add("Get" .. label .. "Texture", "button", getRole(role))
  Typed.add("Clear" .. label .. "Texture", "button", clearRole(role))
end

Typed.add("SetCheckedTexture", "checkbutton", setRoleSource("checked", false))
Typed.add("GetCheckedTexture", "checkbutton", getRole("checked"))
Typed.add("SetDisabledCheckedTexture", "checkbutton", setRoleSource("disabledChecked", false))
Typed.add("GetDisabledCheckedTexture", "checkbutton", getRole("disabledChecked"))

return M

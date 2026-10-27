-- The object an animation animates. SetTarget, SetChildKey, SetTargetKey, SetTargetName and SetTargetParent each store a
-- spec { kind, value } in st.target (the last call wins); the spec is resolved when asked, so a name or key that is only
-- built later (an XML target) still finds its object. Reads kit state; calls no method of an object.
local M = {}

local AddonEnv = require("addon_env")

local PARENT = "$parent"

-- The owner of the group of animation: the frame or region that called CreateAnimationGroup.
local function ownerOf(w, animation)
  local group = w.ui.state[animation].parent
  local groupState = group and w.ui.state[group]

  return groupState and groupState.parent
end

-- source: assumed (W73) a name is a global with "$parent" standing for the owner's name ("$parent" alone is the owner), as
-- an XML relativeTo is (ui/xml_layout.lua nameTarget); the Blizzard XML writes target="$parentGlow".
local function byName(w, animation, name)
  local owner = ownerOf(w, animation)
  if name == PARENT then
    return owner
  end
  local ownerState = owner and w.ui.state[owner]
  local ownerName = ownerState and ownerState.name or ""

  return AddonEnv.global(w, (name:gsub("%$parent", ownerName)), true)
end

-- source: confirmed (W73) Blizzard XML targetKey="$parent.$parent.MedalGlow" (blizzard_framexml/mists/worldstateframe.xml,
-- on an Alpha in a group kept at parentKey of the frame): "$parent" goes to the parent of the object so far, starting at
-- the animation, and any other segment is a field.
local function byKey(w, animation, path)
  local current = animation
  for segment in path:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    local state = w.ui.state[current]
    if segment == PARENT then
      current = state and state.parent
    else
      current = current[segment]
    end
  end

  return current
end

-- source: confirmed (W73) Blizzard XML childKey="SpellHighlightTexture" on an Alpha in the group of an action button
-- (blizzard_actionbar/mainline/actionbuttontemplate.xml:76): a field of the owner.
local function byChildKey(w, animation, key)
  local owner = ownerOf(w, animation)

  return owner and owner[key]
end

local RESOLVERS = {
  Target = function(w, animation, value)
    if type(value) == "string" then
      return byName(w, animation, value)
    end

    return w.ui.state[value] and value or ownerOf(w, animation)
  end,
  ChildKey = byChildKey,
  TargetKey = byKey,
  TargetName = byName,
  TargetParent = ownerOf,
}

-- The spec the setter of kind stores for the animation state st.
function M.set(st, kind, value)
  st.target = { kind = kind, value = value }

  return true
end

-- The target of animation: what its last target setter names, nil when that names nothing built yet; the owner of its
-- group when no setter was called.
function M.resolve(w, animation)
  local spec = w.ui.state[animation].target
  if not spec then
    return ownerOf(w, animation)
  end
  local found = RESOLVERS[spec.kind](w, animation, spec.value)

  return w.ui.state[found] and found or nil
end

return M

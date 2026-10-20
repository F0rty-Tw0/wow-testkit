-- Menu API picks: reads entry state from descriptions and answers a click with the responder and MenuResponse.
-- Sources: docs/specs/2026-10-19-input-steps-sources.md "Phase 4" (M1-M5, M7, M8); client paths are relative to
-- Interface/AddOns/Blizzard_Menu/.
local M = {}

local MenuFrames = require("framexml.fakes.menu_frames")

-- M7 (MenuConstants.lua:17-23) and M5 (MenuConstants.lua:31-36), identical on all five flavors.
M.RESPONSE = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
M.INPUT_CONTEXT = { None = 1, MouseButton = 2, MouseWheel = 3 }

local RESPONSE = M.RESPONSE
-- M8 (MenuTemplates.lua:341): only a checkbox has a default response; button and radio answer nil, which closes.
local DEFAULT_RESPONSE = { checkbox = RESPONSE.Refresh }
local CHECKED_KINDS = { checkbox = true, radio = true }

-- The level's position in w.menus, or nil when it is not open.
function M.depthOf(w, level)
  for depth, open in ipairs(w.menus) do
    if open == level then
      return depth
    end
  end

  return nil
end

-- The truthiness of fn(...) under addon context; an error is recorded and reads false.
local function truthy(w, fn, ...)
  local result = w:callAsAddon(fn, ...)

  return result[1] and result[2] and true or false
end

-- M4 (Menu.lua:830-844): enabled is nil/true, a boolean, or a function of the description. M2 (:694-699): checked is
-- isSelected(data) for a checkbox or radio, else false. Returns enabled, checked.
function M.readState(w, child)
  local enabled = child.enabled
  if enabled == nil then
    enabled = true
  end
  if type(enabled) == "function" then
    enabled = truthy(w, enabled, child)
  end
  local checked = false
  if CHECKED_KINDS[child.kind] and child.isSelected then
    checked = truthy(w, child.isSelected, child.data)
  end

  return enabled and true or false, checked
end

-- M2 (Menu.lua:1645-1665, SecureReinitializeAll): re-reads enabled/checked of every entry of an open level. Never runs
-- the generator.
function M.reinit(w, level)
  for index, entry in ipairs(level.entries) do
    entry.enabled, entry.checked = M.readState(w, level.node.children[index])
    if entry.frame then
      if entry.enabled then
        entry.frame:Enable()
      else
        entry.frame:Disable()
      end
    end
  end
end

-- M7 (Menu.lua:2219-2268, AttributeRespond): nil/CloseAll close every level, except on a submenu root (nothing
-- closes); Close closes the picked level and deeper; Refresh re-reads the picked level and the submenu attached to the
-- entry; Open does nothing. Every other response then re-reads the shallower levels (:2259-2262).
local function respond(w, level, depth, index, response)
  if response == nil or response == RESPONSE.CloseAll then
    if #level.node.children[index].children == 0 then
      MenuFrames.close(w, 1)
    end

    return
  end
  if response == RESPONSE.Close then
    MenuFrames.close(w, depth)
  elseif response == RESPONSE.Refresh then
    M.reinit(w, level)
    local sub = w.menus[depth + 1]
    if sub and sub.parentIndex == index then
      M.reinit(w, sub)
    end
  end
  for shallower = depth - 1, 1, -1 do
    M.reinit(w, w.menus[shallower])
  end
end

-- M1, M3 (Menu.lua:885-893): the responder is the callback (button) or setSelected (checkbox, radio).
local function responderOf(child)
  if child.kind == "button" then
    return child.callback
  end

  return CHECKED_KINDS[child.kind] and child.setSelected or nil
end

-- M8 (Menu.lua:903-947, Pick): returns the level's pick(index, button). The entry must exist, have a responder and be
-- enabled (re-read now, :910-913); otherwise nothing happens and the menu stays.
function M.forLevel(w, level)
  return function(index, button)
    local child = level.node.children[index]
    local responder = child and responderOf(child)
    if not responder or not M.readState(w, child) then
      return
    end
    local input = { context = M.INPUT_CONTEXT.MouseButton, buttonName = button or "LeftButton" }
    local result = w:callAsAddon(responder, child.data, input, level.frame)
    local response = DEFAULT_RESPONSE[child.kind]
    if result[1] and result[2] then
      response = result[2]
    end
    -- grug: unsourced; the client would apply the response to the menu manager, which the kit does not model.
    local depth = M.depthOf(w, level)
    if not depth or w.menus[1].state ~= level.state then
      return
    end
    respond(w, level, depth, index, response)
  end
end

return M

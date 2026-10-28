-- Blizzard's own windows on the opt-in layer (Phase 12): which window addons exist in the extract, which load at startup
-- (Ruling C3), and loading one on demand with the addon that defines ShowUIPanel. Data in blizzard_window_specs.lua.
local M = {}

local BlizzardUi = require("blizzard_ui")
local Specs = require("blizzard_window_specs")
local State = require("game.state")
local fs = require("fs")

M.WINDOWS, M.BASE, M.SHARED = Specs.WINDOWS, Specs.BASE, Specs.SHARED

local function specsOf(w)
  return w.windowSpecs or M.WINDOWS[w.flavor]
end

-- The window's spec on w's flavor (w.windowSpecs, when set, replaces the flavor's whole table), or nil.
function M.spec(w, window)
  return specsOf(w)[window]
end

-- Enum.PlayerInteractionType[name] as the world installed it (never a literal here), or nil.
function M.interaction(name)
  local types = _G.Enum and _G.Enum.PlayerInteractionType
  return types and types[name] or nil
end

local function inExtract(w, addon)
  return w.client ~= nil and fs.isdir(w.client.dir .. "/code/addons/" .. addon:lower())
end

local function sortedNames(specs)
  local names = {}
  for name in pairs(specs) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

-- Sorted names of the windows whose addon folder is in the extract; {} without the layer.
function M.available(w)
  local found = {}
  if w.blizzard then
    local specs = specsOf(w)
    for _, name in ipairs(sortedNames(specs)) do
      if inExtract(w, specs[name].addon) then
        found[#found + 1] = name
      end
    end
  end
  return found
end

-- Ruling C3: the addons that load with the layer, in order: SHARED, then the addon of every window with lod == false (in
-- window-name order), each once and only when its folder is in the extract.
function M.startup(w)
  local names, seen = {}, {}
  local function add(addon)
    if not seen[addon] and inExtract(w, addon) then
      seen[addon] = true
      names[#names + 1] = addon
    end
  end
  for _, addon in ipairs(M.SHARED[w.flavor]) do
    add(addon)
  end
  local specs = specsOf(w)
  for _, name in ipairs(sortedNames(specs)) do
    if specs[name].lod == false then
      add(specs[name].addon)
    end
  end
  return names
end

-- source: assumed the kit's ShowUIPanel / HideUIPanel when no loaded addon defines them: they show and hide the frame
-- (the real ones also position it among the panels).
local function installPanelFallbacks(w)
  if _G.ShowUIPanel == nil then
    State.define(w, "ShowUIPanel", function(frame)
      frame:Show()
    end, State.ALL)
  end
  if _G.HideUIPanel == nil then
    State.define(w, "HideUIPanel", function(frame)
      frame:Hide()
    end, State.ALL)
  end
end

-- Loads BASE, then the window's addon and its `also` addons (an addon already loaded stays, B3). A BASE or `also` addon
-- the extract lacks is skipped with a note; only the window's own addon missing returns nil, "MISSING".
function M.loadFor(w, window)
  local spec = M.spec(w, window)
  local function load(addon)
    local ok, reason = BlizzardUi.loadOne(w, addon)
    if not ok then
      table.insert(w.blizzard.notes, "Blizzard windows: " .. addon .. " " .. tostring(reason))
    end
    return ok, reason
  end
  for _, addon in ipairs(M.BASE[w.flavor]) do
    load(addon)
  end
  local ok, reason = load(spec.addon)
  if not ok then
    return nil, reason
  end
  for _, addon in ipairs(spec.also or {}) do
    load(addon)
  end
  installPanelFallbacks(w)
  return true
end

return M

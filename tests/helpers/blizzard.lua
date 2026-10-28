-- Blizzard UI layer test helpers: kit-authored mini "Blizzard" addons (never Blizzard text) written into a temp client
-- extract laid out as tools/client lays it out (code/addons/<lowercase name>/<lowercase file>), and a scenario run that
-- loads them as the layer before a probe addon.
local H = require("tests.helpers.client")
local Scenario = require("scenario")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local M = {}

local BUILD = "70575"

M.MINI = {
  blizzard_minibase = {
    toc = "## Interface: 120100\nMiniBase.lua\n",
    files = {
      ["minibase.lua"] = [[
MiniLog = MiniLog or {}
MiniLog[#MiniLog + 1] = "base"
FACTION_HORDE = "Mini Horde"
MiniSecure = issecure()
function MiniCheck() MiniSeen = issecure() end
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name) MiniLog[#MiniLog + 1] = "adl:" .. name end)
]],
    },
  },
  blizzard_minibar = {
    toc = "## Interface: 120100\n## Dependencies: Blizzard_MiniBase\n"
      .. "## Dep: Blizzard_MiniBase [AllowLoadGameType mainline]\n## Dep: Blizzard_Gone [AllowLoadGameType classic]\n"
      .. "MiniBar.xml\nMiniMore.lua\n",
    files = {
      ["minibar.xml"] = '<Ui><Frame name="MiniBar" parent="UIParent"><Size x="200" y="40"/><Anchors><Anchor point="BOTTOM" y="45"/></Anchors></Frame><Script file="MiniBar.lua"/></Ui>',
      ["minibar.lua"] = 'MiniLog[#MiniLog + 1] = "bar"\n',
      ["minimore.lua"] = 'MiniLog[#MiniLog + 1] = "more"\n',
      ["bindings.xml"] = '<Bindings><Binding name="MINI_TOGGLE">MiniLog[#MiniLog + 1] = "toggle"</Binding></Bindings>',
    },
  },
  blizzard_framexml = { -- not a target: holds the default bindings file only
    toc = "## Interface: 120100\n",
    files = {
      ["bindings_standard.xml"] = '<Bindings><Binding name="MINI_DEFAULT">MiniLog = MiniLog or {}; MiniLog[#MiniLog + 1] = "default"</Binding></Bindings>',
    },
  },
}

local function copyAddon(addon)
  local files = {}
  for path, text in pairs(addon.files or {}) do
    files[path] = text
  end
  return { toc = addon.toc, tocFile = addon.tocFile, files = files }
end

-- A deep copy of M.MINI with overrides[name].toc / .tocFile / .files[path] replaced (a new name adds an addon).
function M.mini(overrides)
  local addons = {}
  for name, addon in pairs(M.MINI) do
    addons[name] = copyAddon(addon)
  end
  for name, over in pairs(overrides or {}) do
    local addon = addons[name] or { files = {} }
    addon.toc = over.toc or addon.toc
    addon.tocFile = over.tocFile or addon.tocFile
    for path, text in pairs(over.files or {}) do
      addon.files[path] = text
    end
    addons[name] = addon
  end
  return addons
end

-- Writes addons under root as a retail extract (each TOC as <name>.toc unless tocFile names it) and returns the extract
-- Client.find would answer for it.
function M.extract(root, addons)
  local files = {}
  for name, addon in pairs(addons) do
    local dir = "code/addons/" .. name .. "/"
    files[dir .. (addon.tocFile or name .. ".toc")] = addon.toc
    for path, text in pairs(addon.files) do
      files[dir .. path] = text
    end
  end
  return H.extract(root, "retail", BUILD, files)
end

-- A temp addon folder Probe (Probe.toc, Probe.lua = lua or ""); returns its root.
function M.probe(lua)
  local root = Tmp.dir("bzprobe") .. "/Probe"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Probe.toc", "## Interface: 120100\nProbe.lua\n")
  fs.writeFile(root .. "/Probe.lua", lua or "")
  return root
end

-- Runs a retail scenario of Probe with the layer on addons: opts = { targets?, lua?, before?, screen? }. Calls
-- opts.before(s) before s:login() and fn(s) after it, destroys the world and rethrows the report's first error when it
-- failed (so assertions inside fn fail the test). Returns the report.
function M.run(addons, opts, fn)
  local extract = M.extract(Tmp.dir("bzx"), addons)
  local matrixOpts = {
    addon = "Probe",
    root = M.probe(opts.lua),
    blizzardUi = { targets = opts.targets },
    client = extract,
    findClient = function() end,
    screen = opts.screen or { width = 1000, height = 800 },
  }
  local report = Scenario.matrix({ "retail" }, function(s)
    if opts.before then
      opts.before(s)
    end
    s:login()
    fn(s)
  end, matrixOpts).retail
  if report.status == "fail" then
    error(tostring(report.errors[1].message), 0)
  end
  return report
end

return M

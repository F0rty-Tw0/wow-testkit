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
  blizzard_minibuttons = {
    toc = "## Interface: 120100\n## Dependencies: Blizzard_MiniBar\nMiniButtons.xml\n",
    files = {
      ["minibuttons.xml"] = '<Ui><CheckButton name="MiniActionButtonTemplate" virtual="true"><Size x="36" y="36"/><Layers><Layer level="ARTWORK"><Texture parentKey="Icon" setAllPoints="true"/></Layer></Layers></CheckButton><Script file="MiniButtons.lua"/></Ui>',
      ["minibuttons.lua"] = [[
local button = CreateFrame("CheckButton", "MiniBarButton1", MiniBar, "MiniActionButtonTemplate")
button:SetID(1)
button:SetPoint("LEFT")
button.Count = button:CreateFontString(nil, "OVERLAY")
button.Count:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
button:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
button:SetScript("OnEvent", function(self, _, slot)
  if slot == self:GetID() then
    self.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
    self.Count:SetText(C_ActionBar.GetActionDisplayCount(slot))
  end
end)
]],
    },
  },
  blizzard_minieditmode = {
    toc = "## Interface: 120100\n## Dependencies: Blizzard_MiniBar\nMiniEditMode.lua\n",
    files = {
      -- activeLayout counts the two preset layouts the client prepends, so the saved layout is info.layouts[active - 2].
      ["minieditmode.lua"] = [[
local f = CreateFrame("Frame")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:SetScript("OnEvent", function()
  local info = C_EditMode.GetLayouts()
  local layout = info.layouts[info.activeLayout - 2]
  for _, sys in ipairs(layout and layout.systems or {}) do
    if sys.system == 0 then
      local a = sys.anchorInfo
      MiniBar:ClearAllPoints()
      MiniBar:SetPoint(a.point, UIParent, a.relativePoint, a.offsetX, a.offsetY)
    end
  end
end)
]],
    },
  },
  blizzard_miniunit = { -- no dependencies
    toc = "## Interface: 120100\nMiniUnit.lua\n",
    files = {
      ["miniunit.lua"] = [[
local f = CreateFrame("Frame", "MiniPlayerFrame", UIParent)
f:SetSize(120, 40)
f:SetPoint("TOPLEFT", 10, -20)
f.Portrait = f:CreateTexture(nil, "ARTWORK")
f.Name = f:CreateFontString(nil, "OVERLAY")
f.Name:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
f.HealthBar = CreateFrame("StatusBar", nil, f)
local function update()
  f.Name:SetText(UnitName("player"))
  f.HealthBar:SetMinMaxValues(0, UnitHealthMax("player"))
  f.HealthBar:SetValue(UnitHealth("player"))
  SetPortraitTexture(f.Portrait, "player")
  f.Role, f.Mark = UnitGroupRolesAssigned("player"), GetRaidTargetIndex("player")
end
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", update)
]],
    },
  },
  blizzard_miniwindow = {
    toc = "## Interface: 120100\n## LoadOnDemand: 1\nMiniWindow.lua\n",
    files = {
      ["miniwindow.lua"] = [[
MiniWindowLoads = (MiniWindowLoads or 0) + 1
local f = CreateFrame("Frame", "MiniWindowFrame", UIParent)
f:SetSize(300, 200)
f:SetPoint("CENTER")
f:Hide()
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
f:SetScript("OnEvent", function(self, event, ...)
  MiniWindowShownBy = event .. ":" .. tostring((...)) -- the trigger the test reads
  ShowUIPanel(self)
end)
function MiniWindowShow() MiniWindowShownBy = "show-global"; MiniWindowFrame:Show() end -- stands in for MailFrame_Show
]],
    },
  },
  blizzard_minitalents = { -- Task 12.3: a toggle global that lists the talents the store answers, one FontString each
    toc = "## Interface: 120100\n## LoadOnDemand: 1\nMiniTalents.lua\n",
    files = {
      ["minitalents.lua"] = [[
local f = CreateFrame("Frame", "MiniTalentFrame", UIParent)
f:SetSize(300, 200)
f:SetPoint("CENTER")
f:Hide()
f.lines = {}
local function names()
  local out = {}
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID() then
    local config = C_ClassTalents.GetActiveConfigID()
    for _, node in ipairs(C_Traits.GetTreeNodes(C_Traits.GetConfigInfo(config).treeIDs[1])) do
      local entry = C_Traits.GetEntryInfo(config, C_Traits.GetNodeInfo(config, node).entryIDs[1])
      out[#out + 1] = C_Spell.GetSpellInfo(C_Traits.GetDefinitionInfo(entry.definitionID).spellID).name
    end
  else
    for i = 1, GetNumTalents(1) do
      out[#out + 1] = (GetTalentInfo(1, i))
    end
  end
  return out
end
function MiniToggleTalents()
  for i, name in ipairs(names()) do
    local line = f.lines[i] or f:CreateFontString(nil, "OVERLAY")
    line:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    line:SetPoint("TOPLEFT", 10, -20 * i)
    line:SetText(name)
    f.lines[i] = line
  end
  f:Show()
end
]],
    },
  },
  blizzard_minieager = { -- C3: no LoadOnDemand line, so it loads with the layer
    toc = "## Interface: 120100\nMiniEager.lua\n",
    files = {
      ["minieager.lua"] = [[
MiniEagerLoads = (MiniEagerLoads or 0) + 1
local f = CreateFrame("Frame", "MiniEagerFrame", UIParent)
f:Hide()
f:RegisterEvent("MAIL_SHOW")
f:SetScript("OnEvent", function(self) ShowUIPanel(self) end)
]],
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

-- Writes addons under root as an extract of flavor (default retail; each TOC as <name>.toc unless tocFile names it) and
-- returns the extract Client.find would answer for it.
function M.extract(root, addons, flavor)
  local files = {}
  for name, addon in pairs(addons) do
    local dir = "code/addons/" .. name .. "/"
    files[dir .. (addon.tocFile or name .. ".toc")] = addon.toc
    for path, text in pairs(addon.files) do
      files[dir .. path] = text
    end
  end
  return H.extract(root, flavor or "retail", BUILD, files)
end

-- A temp addon folder Probe (Probe.toc = "## <header>", default "Interface: 120100"; Probe.lua = lua or ""); returns its root.
function M.probe(lua, header)
  local root = Tmp.dir("bzprobe") .. "/Probe"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Probe.toc", "## " .. (header or "Interface: 120100") .. "\nProbe.lua\n")
  fs.writeFile(root .. "/Probe.lua", lua or "")
  return root
end

-- Runs a scenario of Probe with the layer on addons: opts = { targets?, lua?, header?, before?, screen?, flavor? = "retail" }.
-- Calls opts.before(s) before s:login() and fn(s) after it, destroys the world and rethrows the report's first error when
-- it failed (so assertions inside fn fail the test). Returns the report.
function M.run(addons, opts, fn)
  local flavor = opts.flavor or "retail"
  local extract = M.extract(Tmp.dir("bzx"), addons, flavor)
  local matrixOpts = {
    addon = "Probe",
    root = M.probe(opts.lua, opts.header),
    blizzardUi = { targets = opts.targets },
    client = extract,
    findClient = function() end,
    screen = opts.screen or { width = 1000, height = 800 },
  }
  local report = Scenario.matrix({ flavor }, function(s)
    if opts.before then
      opts.before(s)
    end
    s:login()
    fn(s)
  end, matrixOpts)[flavor]
  if report.status == "fail" then
    error(tostring(report.errors[1].message), 0)
  end
  return report
end

return M

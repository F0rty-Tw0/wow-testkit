-- Root <Font> and <FontFamily> elements: each builds the global font object it names. virtual="true" makes no template
-- of a font: it is a named object either way.
-- source: confirmed (row X34) forever 70862 blizzard_fonts_shared/shared/fontstyles.xml:172 declares
-- `<Font name="GameFontNormalLarge" ... virtual="true">` and blizzard_uipanels_game/camelot/pvprankframe.lua:238 indexes
-- the global GameFontNormalLarge; compactunitframe.xml:31-32 FontStrings inherit the virtual GameFontDisable and
-- compactunitframe.lua:1948-1952 multiplies the size their GetFont returns.
local M = {}

local AddonEnv = require("addon_env")
local FontChain = require("ui.font_chain")
local XmlBuild = require("ui.xml_build")
local XmlLayout = require("ui.xml_layout")

-- source: forever 70862 ui.xsd:52-58 OUTLINETYPE; the SetFont flags each value stands for are assumed (row X34).
local OUTLINE_FLAGS = { NONE = "", NORMAL = "OUTLINE", THICK = "THICKOUTLINE" }
-- source: assumed (row X34) the kit plays an enUS client, so a <FontFamily> is its alphabet="roman" member.
local ALPHABET = "roman"
-- ui.xsd:493-515 FontType attributes read by apply, and the rendering-only ones the kit has no state for.
local KNOWN = {
  name = true,
  virtual = true,
  inherits = true,
  font = true,
  height = true,
  outline = true,
  justifyh = true,
  justifyv = true,
  spacing = true,
  fixedsize = true,
  filter = true,
  canbeuserscaled = true,
  slug = true,
}

local function inherit(w, font, node, session)
  local name = node.attrs.inherits
  local parent = AddonEnv.global(w, name, true)
  local st = type(parent) == "table" and w.ui.state[parent]
  if st and st.plan.isA.font then
    font:SetFontObject(parent)
  else
    session.reportAt(node.line, "font object '" .. name .. "' not found; inherits ignored")
  end
end

-- font, height (or <FontHeight>) and outline over what the inherited font object gives; none of them keeps the
-- inherited font live.
local function setFont(w, font, node, session)
  local attrs = node.attrs
  local heightNode = XmlLayout.childNamed(node, "fontheight")
  local height = tonumber(attrs.height) or (heightNode and XmlLayout.absValue(heightNode))
  local flags = attrs.outline and OUTLINE_FLAGS[attrs.outline:upper()]
  if attrs.outline and not flags then
    session.reportAt(node.line, "outline '" .. attrs.outline .. "' is not an OUTLINETYPE; ignored")
  end
  if attrs.font or height or flags then
    local base = FontChain.inherited(w, w.ui.state[font], "font") or {}
    font:SetFont(attrs.font or base[1], height or base[2], flags or base[3] or "")
  end
end

-- Builds node's font object content on font: inherits, the font, justify and spacing, then the Color and Shadow children.
local function apply(w, font, node, session)
  local attrs = node.attrs
  if attrs.inherits then
    inherit(w, font, node, session)
  end
  setFont(w, font, node, session)
  if attrs.justifyh then
    font:SetJustifyH(attrs.justifyh)
  end
  if attrs.justifyv then
    font:SetJustifyV(attrs.justifyv)
  end
  if tonumber(attrs.spacing) then
    font:SetSpacing(tonumber(attrs.spacing))
  end
  for name in pairs(attrs) do
    if not KNOWN[name] then
      session.report("attr:" .. name, "unsupported XML attribute '" .. name .. "' ignored")
    end
  end
  for _, child in ipairs(node.children) do
    if child.tag ~= "fontheight" then
      XmlBuild.child(w, font, child, session)
    end
  end
end

function M.font(w, node, session)
  if not node.attrs.name then
    session.reportAt(node.line, "<Font> needs a name; ignored")
    return
  end
  apply(w, w.ui.create("Font", node.attrs.name), node, session)
end

function M.family(w, node, session)
  if not node.attrs.name then
    session.reportAt(node.line, "<FontFamily> needs a name; ignored")
    return
  end
  for _, member in ipairs(node.children) do
    local font = member.tag == "member" and member.attrs.alphabet == ALPHABET and XmlLayout.childNamed(member, "font")
    if font then
      apply(w, w.ui.create("Font", node.attrs.name), font, session)
      return
    end
  end
  session.reportAt(node.line, "<FontFamily> has no " .. ALPHABET .. " member with a <Font>; ignored")
end

return M

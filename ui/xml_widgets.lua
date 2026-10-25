-- XML extras of buttons, font strings and legacy backdrops: state textures, ButtonText, FontHeight, Shadow, Backdrop.
local M = {}

local XmlBuild = require("ui.xml_build")
local XmlLayout = require("ui.xml_layout")

local handlers = XmlBuild.handlers

-- Button state tags to the setter that stores the texture (the button keeps it for its state).
local STATE_TEXTURES = {
  normaltexture = "SetNormalTexture",
  pushedtexture = "SetPushedTexture",
  highlighttexture = "SetHighlightTexture",
}

-- A copy of node that builds as `tag`, so the region builder takes a <NormalTexture> for a Texture and a <ButtonText>
-- for a FontString.
local function asTag(node, tag, rawTag)
  return { tag = tag, rawTag = rawTag, attrs = node.attrs, children = node.children, line = node.line }
end

-- The texture runs its own Size, Anchors, TexCoords and Color children; the button then stores it (row X17 for
-- `alphaMode`, assumed).
local function stateTexture(setter)
  return function(w, button, _, node, session)
    local texture = XmlBuild.region(w, asTag(node, "texture", "Texture"), button, session)
    if texture then
      button[setter](button, texture)
    end
  end
end

for tag, setter in pairs(STATE_TEXTURES) do
  handlers[tag] = stateTexture(setter)
end

function handlers.buttontext(w, button, _, node, session)
  local text = XmlBuild.region(w, asTag(node, "fontstring", "FontString"), button, session)
  if text then
    button:SetFontString(text)
  end
end

function handlers.fontheight(_, text, _, node)
  local height = XmlLayout.absValue(node)
  if height then
    text:SetTextHeight(height)
  end
end

function handlers.shadow(_, text, _, node)
  for _, child in ipairs(node.children) do
    if child.tag == "offset" then
      text:SetShadowOffset(XmlLayout.dimension(child))
    elseif child.tag == "color" then
      text:SetShadowColor(XmlLayout.color(child))
    end
  end
end

local function insets(node)
  local container = XmlLayout.childNamed(node, "backgroundinsets")
  local inset = container and container.children[1]
  if not inset then
    return nil
  end
  local attrs = inset.attrs
  return { left = tonumber(attrs.left), right = tonumber(attrs.right), top = tonumber(attrs.top), bottom = tonumber(attrs.bottom) }
end

local function sizeOf(node, tag)
  local child = XmlLayout.childNamed(node, tag)
  return child and XmlLayout.absValue(child)
end

-- The legacy <Backdrop> as the info table SetBackdrop takes; only a frame with BackdropTemplate has SetBackdrop.
function handlers.backdrop(_, frame, _, node, session)
  if not frame.SetBackdrop then
    session.reportAt(node.line, "<Backdrop> needs BackdropTemplate; ignored")
    return
  end
  local attrs = node.attrs
  frame:SetBackdrop({
    bgFile = attrs.bgfile,
    edgeFile = attrs.edgefile,
    tile = attrs.tile == "true",
    tileSize = sizeOf(node, "tilesize"),
    edgeSize = sizeOf(node, "edgesize"),
    insets = insets(node),
  })
end

return M

-- XML intrinsic frame types: an element with intrinsic="true" declares the frame type its name gives, based on the
-- element's tag. Every frame of that type gets the element's content (attributes, KeyValues, regions, children) when it
-- is created, before its template list or its own XML content; the element's scripts become the type's intrinsic
-- handlers. XmlBuild.frame hands such an element here instead of building it.
-- source: wiki Intrinsic_frame: "The `name` attribute becomes the new tag name in XML or the frame type in
-- CreateFrame"; "GetObjectType returns the intrinsic's type, not the intrinsic's name" (rows X24, D8).
local M = {}

local Scripts = require("ui.scripts")
local Widgets = require("ui.widgets")
local XmlBuild = require("ui.xml_build")
local XmlScripts = require("ui.xml_scripts")

-- node without its <Scripts>, the content applied to each new frame of the type.
local function content(node)
  local copy, children = {}, {}
  for key, value in pairs(node) do
    copy[key] = value
  end
  for _, child in ipairs(node.children) do
    if child.tag ~= "scripts" then
      children[#children + 1] = child
    end
  end
  copy.children = children
  return copy
end

-- The element's handlers as the type's intrinsic scripts: before the frame's own script, or after it and its hooks.
-- source: wiki Intrinsic_frame: `intrinsicOrder="precall"` runs "before the normal script handler", "postcall" after
-- it, and the default "will default to "precall""; "Intrinsic scripts cannot be removed after being defined" (row X24).
local function intrinsicScripts(w, node, baseType, session)
  local pre, post = {}, {}
  for _, scripts in ipairs(node.children) do
    for _, child in ipairs(scripts.tag == "scripts" and scripts.children or {}) do
      local name = Scripts.canonical(baseType, child.tag, w.flavor)
      local fn = name and XmlScripts.handlerFunction(w, child, session, nil)
      if not name then
        session.reportAt(child.line, baseType .. " has no script handler '" .. child.rawTag .. "'; ignored")
      elseif fn then
        local order = child.attrs.intrinsicorder == "postcall" and post or pre
        order[name] = function(world, obj, _, ...)
          world:callAsAddon(fn, obj, ...)
        end
      end
    end
  end
  return pre, post
end

-- Registers the intrinsic element `node` as a frame type of this world; a later declaration of the name replaces it, a
-- kit fake's included (Widgets.registerIntrinsic).
function M.declare(w, node, session)
  local name = node.attrs.name
  if not name then
    session.reportAt(node.line, "intrinsic <" .. node.rawTag .. "> needs a name; ignored")
    return
  end
  local baseType = Widgets.resolveType(w, node.rawTag)
  local body = content(node)
  local pre, post = intrinsicScripts(w, node, baseType, session)
  Widgets.registerIntrinsic(w, name, baseType, {
    init = function(world, obj)
      XmlBuild.applyTemplate(world, obj, body, session)
    end,
    scripts = pre,
    postScripts = post,
  })
end

return M

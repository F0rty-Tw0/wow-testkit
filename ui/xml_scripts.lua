-- XML <Scripts>: a handler per child element (inline body, function= or method=), set on the frame through its own
-- SetScript, then the OnLoad and OnShow a frame gets once it is built. Registered in XmlBuild's handlers and finishers.
local M = {}

local Scripts = require("ui.scripts")
local XmlBuild = require("ui.xml_build")

-- Handler name to the argument names an inline body sees after `self` (row X12: OnClick, OnValueChanged confirmed; the
-- others assumed, from the Widget_script_handlers signatures); any other handler gets "...".
local ARGS = {
  OnEvent = "event, ...",
  OnClick = "button, down",
  OnUpdate = "elapsed",
  OnEnter = "motion",
  OnLeave = "motion",
  OnMouseDown = "button",
  OnMouseUp = "button, upInside",
  OnMouseWheel = "delta",
  OnValueChanged = "value, userInput",
  OnTextChanged = "userInput",
  OnSizeChanged = "width, height",
  OnAttributeChanged = "name, value",
  OnDragStart = "button",
  OnDragStop = "button",
  OnChar = "text",
  OnKeyDown = "key",
  OnKeyUp = "key",
}
local DEFAULT_ARGS = "..."

-- source: wiki XML/Scripts, `function` "Name of a function instead of Lua code between the XML tags". The global is
-- looked up now, in the addon's environment (row X12, when assumed).
local function namedFunction(node, session)
  local name = node.attrs["function"]
  local fn = session.ctx.env[name]
  if type(fn) ~= "function" then
    session.reportAt(node.line, "script function '" .. name .. "' not found; " .. node.rawTag .. " ignored")
    return nil
  end
  return fn
end

-- source: wiki XML/Scripts, `method` "Name of a widget method instead of Lua code between the XML tags". The handler's
-- arguments are passed on (row X12, assumed).
local function namedMethod(node)
  local name = node.attrs.method
  return function(self, ...)
    return self[name](self, ...)
  end
end

-- source: Blizzard_FrameXML/SecureTemplates.xml:16, `<OnClick>` uses `self`, `button`, `down` as locals (row X12). The
-- header shares the body's first line, so an error names the XML line the body starts on.
local function inlineBody(node, session)
  local ctx = session.ctx
  local source = "return function(self, " .. (ARGS[node.rawTag] or DEFAULT_ARGS) .. ") " .. node.text .. "\nend"
  local chunk = ctx.compile(source, "addon:" .. ctx.name .. "/" .. session.file.path, node.textLine)
  return chunk and chunk()
end

-- source: wiki XML/Scripts, `inherit` "Hooks (prepend, append) other scripts inherited through an XML virtual
-- template" (row X4); which order each gives is assumed: prepend runs the new handler first, append last.
local function combine(new, inherited, mode)
  if mode == "prepend" then
    return function(self, ...)
      new(self, ...)
      return inherited(self, ...)
    end
  elseif mode == "append" then
    return function(self, ...)
      inherited(self, ...)
      return new(self, ...)
    end
  end
  return new
end

-- The function for one handler element `node` (<OnLoad>, <OnClick>, ...): function= the named global, method= a call of
-- that widget method, else the element's text as a body. `inherited` is the handler already on the frame; inherit=
-- "prepend" or "append" runs both, otherwise the new one replaces it. Nil when there is nothing to set (reported).
-- The parser lowercases tags, so the canonical OnXxx name is the node's rawTag.
function M.handlerFunction(_, _, node, session, inherited)
  local fn
  if node.attrs["function"] then
    fn = namedFunction(node, session)
  elseif node.attrs.method then
    fn = namedMethod(node)
  else
    fn = inlineBody(node, session)
  end
  if fn and inherited then
    return combine(fn, inherited, node.attrs.inherit)
  end
  return fn
end

function XmlBuild.handlers.scripts(w, frame, st, node, session)
  for _, child in ipairs(node.children) do
    local name = child.rawTag
    if not Scripts.supports(st.plan.type, name, w.flavor) then
      session.reportAt(child.line, st.plan.type .. " has no script handler '" .. name .. "'; ignored")
    else
      local fn = M.handlerFunction(w, frame, child, session, w:getScript(frame, name))
      if fn then
        frame:SetScript(name, fn)
      end
    end
  end
end

-- source: wiki API:CreateFrame, "Fires the frame's OnLoad script"; Blizzard_Menu/Mainline/MenuTemplates.xml:66-117 (row
-- X5): the mixin, KeyValues, child frames and layer regions exist at OnLoad, so this runs after the body. A child
-- finishes before its parent, so its OnLoad runs first (assumed).
-- source: wiki UIHANDLER_OnShow, "if a frame is defined in XML then OnShow also fires after OnLoad unless hidden at the
-- time" (row X6; a hidden parent suppressing it is assumed). A hidden frame fires neither OnShow nor OnHide (row X7).
table.insert(XmlBuild.finishers, function(w, frame)
  w:callScript(frame, "OnLoad")
  if frame:IsVisible() then
    w:callScript(frame, "OnShow")
  end
end)

return M

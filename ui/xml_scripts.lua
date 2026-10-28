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
-- The same by the parser's lowercased tag, so an element in any case finds its arguments.
local ARGS_BY_TAG = {}
for name, args in pairs(ARGS) do
  ARGS_BY_TAG[name:lower()] = args
end

local handlers = XmlBuild.handlers

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
-- arguments are passed on (row X12, assumed). A frame without the method when the handler fires (a mixin that failed to
-- load, say) raises an error that names the method and the XML line, so it lands in w.errors like any handler error.
local function namedMethod(node, session)
  local name = node.attrs.method
  local where = "addon:" .. session.ctx.name .. "/" .. session.file.path .. ":" .. node.line
  return function(self, ...)
    local method = self[name]
    if type(method) ~= "function" then
      error(where .. ": <" .. node.rawTag .. "> method '" .. name .. "' not found on " .. (self:GetName() or self:GetObjectType()), 0)
    end
    return method(self, ...)
  end
end

-- source: Blizzard_FrameXML/SecureTemplates.xml:16, `<OnClick>` uses `self`, `button`, `down` as locals (row X12). The
-- header shares the body's first line, so an error names the XML line the body starts on. The body must compile alone as
-- a block first: text such as `end, boom(), function(self)` would otherwise close the wrapper and run at load. The
-- wrapper chunk then runs protected, so whatever it does reaches w.errors and the load goes on.
local function inlineBody(w, node, session)
  local ctx = session.ctx
  local chunkName = "addon:" .. ctx.name .. "/" .. session.file.path
  if not ctx.compile(node.text, chunkName, node.textLine) then
    return nil
  end
  local source = "return function(self, " .. (ARGS_BY_TAG[node.tag] or DEFAULT_ARGS) .. ") " .. node.text .. "\nend"
  local chunk = ctx.compile(source, chunkName, node.textLine)
  local results = chunk and w:callAsAddon(chunk)
  return results and results[1] and results[2] or nil
end

-- source: wiki XML/Scripts, `inherit` "Hooks (prepend, append) other scripts inherited through an XML virtual
-- template" (row X4); which order each gives is assumed: prepend runs the new handler first, append last. (row X22,
-- assumed) an error in the first handler is recorded and the second still runs.
local function combine(w, new, inherited, mode)
  if mode == "prepend" then
    return function(self, ...)
      w:callAsAddon(new, self, ...)
      return inherited(self, ...)
    end
  elseif mode == "append" then
    return function(self, ...)
      w:callAsAddon(inherited, self, ...)
      return new(self, ...)
    end
  end
  return new
end

-- The function for one handler element `node` (<OnLoad>, <OnClick>, ...): function= the named global, method= a call of
-- that widget method, else the element's text as a body. `inherited` is the handler already on the frame; inherit=
-- "prepend" or "append" runs both, otherwise the new one replaces it. Nil when there is nothing to set (reported).
function M.handlerFunction(w, node, session, inherited)
  local fn
  if node.attrs["function"] then
    fn = namedFunction(node, session)
  elseif node.attrs.method then
    fn = namedMethod(node, session)
  else
    fn = inlineBody(w, node, session)
  end
  if fn and inherited then
    return combine(w, fn, inherited, node.attrs.inherit)
  end
  return fn
end

-- source: row X16 (assumed): element tags match ignoring case, so the canonical OnXxx name comes from the frame type's
-- handler list.
function handlers.scripts(w, frame, st, node, session)
  for _, child in ipairs(node.children) do
    local name = Scripts.canonical(st.plan.type, child.tag, w.flavor)
    if not name then
      session.reportAt(child.line, st.plan.type .. " has no script handler '" .. child.rawTag .. "'; ignored")
    else
      local fn = M.handlerFunction(w, child, session, w:getScript(frame, name))
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

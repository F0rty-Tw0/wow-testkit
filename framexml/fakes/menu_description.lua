-- Menu description tree: the object a Menu API generator fills (rootDescription:CreateButton(...) and friends). Pure Lua,
-- no world. Every description, root included, has all builders; an element with children is a submenu.
-- Sources: docs/specs/2026-10-19-input-steps-sources.md "Phase 4" (M1-M4, M10); client paths are relative to
-- Interface/AddOns/Blizzard_Menu/ (Menu.lua, MenuTemplates.lua).
local M = {}

local Description = {}
Description.__index = Description

local function newNode(kind, fields)
  fields.kind = kind
  fields.enabled = true
  fields.children = {}

  return setmetatable(fields, Description)
end

local function addChild(self, kind, fields)
  local child = newNode(kind, fields)
  self.children[#self.children + 1] = child

  return child
end

-- M1 (MenuTemplates.lua:294-306): the callback is the responder; its return value is the response.
function Description:CreateButton(text, callback, data)
  return addChild(self, "button", { text = text, callback = callback, data = data })
end

-- M2, M3 (MenuTemplates.lua:312-319, :340): isSelected(data) is read on render; setSelected is the responder.
function Description:CreateCheckbox(text, isSelected, setSelected, data)
  return addChild(self, "checkbox", { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end

function Description:CreateRadio(text, isSelected, setSelected, data)
  return addChild(self, "radio", { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end

function Description:CreateTitle(text)
  return addChild(self, "title", { text = text })
end

function Description:CreateDivider()
  return addChild(self, "divider", {})
end

function Description:SetScrollMode(height)
  self.scrollHeight = height
end

-- M4 (Menu.lua:830-844): a boolean, or a function called as fn(description) at every (re)initialize and before a pick.
function Description:SetEnabled(enabled)
  self.enabled = enabled

  return self
end

function Description:SetTooltip(fn)
  self.tooltip = fn

  return self
end

-- M10 (Menu.lua:595-598): the tag Menu.ModifyMenu hooks match, and the contextData they receive.
function Description:SetTag(tag, contextData)
  self.tag = tag
  self.contextData = contextData

  return self
end

function M.newRoot()
  return newNode("root", {})
end

return M

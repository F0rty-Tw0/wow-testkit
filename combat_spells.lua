-- Spell facts for the combat world: scenario data in w.mock.spells first, then the client extract's SpellName table,
-- then a placeholder name.
local M = {}

local Client = require("client")

-- Local runs read the extract's DB2 export, tests and CI use kit data (spec ruling R5). The SpellName row's name is
-- Name_lang, as tools/client's export writes it. Nil without an extract or a row.
function M.extractName(w, id)
  local rows = Client.db2(w.client, "SpellName")
  local row = rows and rows[id]
  return row and row.Name_lang or nil
end

-- { spellID, name, iconID, school, castTime } for id: w.mock.spells[id], else a record holding the extract's name, else
-- "Spell <id>".
function M.info(w, id)
  local record = w.mock.spells[id] or { name = M.extractName(w, id) or ("Spell " .. id) }
  return { spellID = id, name = record.name, iconID = record.icon, school = record.school, castTime = record.castTime }
end

return M

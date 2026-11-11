-- Writes <extract>/api.lua: the Enum and Constants tables the extract's own API docs define, and the set of event
-- names they document (row G57), for the kit's framexml/fakes/client.lua to fill into a world whose pinned
-- api/<flavor> data is older than the client.
--   python tools/run51.py --script tools/client_api.lua <extract-dir>
-- Prints the number of tables written (enums incl. <Name>Meta, plus constants) as the last stdout line. Doc files that
-- fail to load are skipped and counted on stderr.
local Docs = require("tools.docs")
local Serialize = require("serialize")
local fs = require("fs")

local DOCS = "/code/addons/blizzard_apidocumentationgenerated"

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local out = ...
if not out then
  io.stderr:write("usage: client_api.lua <extract-dir>\n")
  return 2
end
local entries, errors = Docs.loadDir(out .. DOCS)
if #errors > 0 then
  io.stderr:write(#errors .. " doc load errors skipped\n")
end
local values = Docs.collect(entries)
local events = {}
for _, entry in ipairs(entries) do
  for _, event in ipairs(entry.doc.Events or {}) do
    events[event.LiteralName] = true
  end
end
local api = { enums = values.Enum, constants = values.Constants, events = events }
fs.writeFile(out .. "/api.lua", Serialize.dump(api)) -- raises on failure
print(count(values.Enum) + count(values.Constants))
return 0

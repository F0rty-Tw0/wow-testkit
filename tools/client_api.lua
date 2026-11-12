-- Writes <extract>/api.lua: the Enum and Constants tables the extract's own API docs define, the set of event names
-- they document (row G57) and their function signatures (row G75), for the kit's framexml/fakes/client.lua to fill
-- into a world whose pinned api/<flavor> data is older than the client.
--   python tools/run51.py --script tools/client_api.lua <extract-dir>
-- Prints the number of tables written (enums incl. <Name>Meta, plus constants) as the last stdout line. Doc files that
-- fail to load are skipped and counted on stderr.
local Docs = require("tools.docs")
local Generate = require("tools.generate")
local GenerateDoc = require("tools.generate_doc")
local Manifest = require("manifest")
local Serialize = require("serialize")
local fs = require("fs")

local DOCS = "/code/addons/blizzard_apidocumentationgenerated"
-- Every namespace counts as present here: the install side keeps only those the flavor's own data has.
local EVERY_NAMESPACE = setmetatable({}, {
  __index = function()
    return true
  end,
})

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- The signatures of every function the system docs list, as tools/generate.lua writes them into api/<flavor>.
local function documentedFunctions(entries)
  local part = Manifest.empty()
  local ctx = { known = Generate.knownTypes(entries), report = GenerateDoc.newReport(), listed = EVERY_NAMESPACE }
  for _, entry in ipairs(entries) do
    if entry.doc.Type ~= "ScriptObject" then
      GenerateDoc.addSystem(part, entry.doc, ctx)
    end
  end
  return part.functions
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
local api = { enums = values.Enum, constants = values.Constants, events = events, functions = documentedFunctions(entries) }
fs.writeFile(out .. "/api.lua", Serialize.dump(api)) -- raises on failure
print(count(values.Enum) + count(values.Constants))
return 0

-- Side A of the parity check (tests/wasm/parity.sh): runs the cases of parity_cases.json against SessionDemo through
-- SessionHost.handleJson and drain, as the Python host does, and writes [{ method, reply, events }] to the out file.
-- Replies and events go in as the host's own JSON text, so no re-encoding changes them. Entry 0 is the open (the info
-- reply and the events the login queued) and also carries the kit root and session folder for compare_parity.py.
-- Usage (python tools/run51.py --script): parity_side_a.lua <kit root> <cases.json> <out.json>
local root, casesPath, outPath = ...
local Json = require("json")
local SessionHost = require("session_host")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local sessionDir = Tmp.dir("parity")
local entries = {}

-- Adds { method, reply, events } for the call just made; extra = JSON text of more members, or nil.
local function record(method, reply, events, extra)
  entries[#entries + 1] = string.format('{"method":%s,"reply":%s,"events":%s%s}', Json.encode(method), reply, events, extra or "")
end

local function run(host)
  local extra = string.format(',"root":%s,"sessionDir":%s', Json.encode(root), Json.encode(sessionDir))
  record("open", host:handleJson("info", "{}"), host:drain(), extra)
  for _, case in ipairs(Json.decode(fs.readFile(casesPath))) do
    local reply = host:handleJson(case.method, Json.encode(case.req))
    record(case.method, reply, host:drain())
  end
end

local host = SessionHost.new({
  addonDir = root .. "/tests/fixtures/addons/SessionDemo",
  sessionDir = sessionDir,
  flavor = "auto",
})
local ok, err = pcall(run, host)
host:shutdown()
if not ok then
  error(err, 0)
end
fs.writeFile(outPath, "[" .. table.concat(entries, ",\n") .. "]\n")

return 0

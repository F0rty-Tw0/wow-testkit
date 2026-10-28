-- The slash commands a session answers itself when no addon handler took the line: /run and /script (Lua in a fresh
-- addon environment), /dump <expr>, /reload (the session host performs it after the call) and the kit-only
-- /advance <seconds>. Output and errors go to the session console.
local M = {}

local AddonEnv = require("addon_env")
local Console = require("session_console")
local Serialize = require("serialize")

-- Localized: addon code may assign globals with these names.
local loadstring, setfenv, tonumber, tostring, type = loadstring, setfenv, tonumber, tostring, type

-- The chunk for code in a fresh addon environment; nil after pushing its compile error (or the refusal of a
-- precompiled chunk) as an error line.
local function compile(w, code, name)
  local refusal = AddonEnv.binaryRefusal(code)
  if refusal then
    Console.push(w, "error", refusal)

    return nil
  end
  local chunk, err = loadstring(code, name)
  if not chunk then
    Console.push(w, "error", err)

    return nil
  end
  return setfenv(chunk, AddonEnv.newEnv(w))
end

local function run(sess, code)
  local chunk = compile(sess.w, code, "=/run")
  if chunk then
    sess.w:callAsAddon(chunk)
  end
end

-- A table as Serialize writes it without the leading "return " (tostring when it holds what Serialize cannot write).
local function show(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local ok, text = pcall(Serialize.dump, value)
  if not ok then
    return tostring(value)
  end
  local body = text:gsub("^return ", ""):gsub("\n$", "")
  return body
end

local function dump(sess, expr)
  local chunk = compile(sess.w, "return " .. expr, "=/dump")
  local results = chunk and sess.w:callAsAddon(chunk)
  if not (results and results[1]) then
    return
  end
  for i = 2, math.max(results.n, 2) do
    Console.push(sess.w, "print", show(results[i]))
  end
end

local function reload(sess)
  sess.pendingReload = {}
end

-- A longer advance runs every per-frame timer it covers in one request, so the server would stall on a huge one.
local MAX_ADVANCE = 3600

local function advance(sess, arg)
  local seconds = tonumber(arg)
  if not (seconds and seconds >= 0 and seconds <= MAX_ADVANCE) then
    Console.push(sess.w, "system", "Usage: /advance <seconds> (0 to " .. MAX_ADVANCE .. ")")
    return
  end
  sess.s:advance(seconds)
end

local COMMANDS = { ["/run"] = run, ["/script"] = run, ["/dump"] = dump, ["/reload"] = reload, ["/advance"] = advance }

-- Runs the built-in command line names and returns true; an unknown command becomes a system line and returns false.
function M.run(sess, line)
  local command, args = tostring(line):match("^(%S+)%s*(.-)$")
  local builtin = command and COMMANDS[command:lower()]
  if not builtin then
    Console.push(sess.w, "system", "Unknown command: " .. (command or tostring(line)))
    return false
  end
  builtin(sess, args)
  return true
end

return M

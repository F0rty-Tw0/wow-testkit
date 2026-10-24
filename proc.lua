-- Proc: runs a program through the shell. The one place besides fs.lua that spawns a process. Every argument goes
-- inside double quotes, and an argument the shell would still reinterpret inside them raises instead of running.
local M = {}

-- Localized: addon code may assign a global named os.
local os = os

local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local SIGNAL_STATUS_UNIT = 256

-- Why arg cannot be quoted safely, or nil. Inside double quotes cmd.exe still expands %VAR% (and !VAR! when delayed
-- expansion is on) and the C runtime reads a final backslash before the closing quote as an escape; sh still
-- expands $ and backticks and honours backslashes. A line break ends the command on either shell.
local function refusal(arg, isWindows)
  if arg:find('"', 1, true) then
    return "contains a double quote"
  elseif arg:find("[\r\n]") or arg:find("\0", 1, true) then
    return "contains a line break"
  elseif isWindows and arg:find("[%%^!]") then
    return "contains % ^ or !, which windows cmd expands inside quotes"
  elseif isWindows and arg:sub(-1) == "\\" then
    return "ends with a backslash, which windows would read as an escaped quote"
  elseif not isWindows and arg:find("[$`\\]") then
    return "contains $ ` or a backslash, which posix sh expands inside quotes"
  end
  return nil
end

local function quoted(arg, isWindows)
  local reason = refusal(arg, isWindows)
  if reason then
    error("proc: argument " .. reason .. ": " .. arg:gsub("[%c]", "?"), 0)
  end
  return '"' .. arg .. '"'
end

-- The shell command line running argv with stdout and stderr redirected to logPath. On Windows the whole line gets
-- one more pair of quotes, which cmd /c strips.
function M.command(argv, logPath, isWindows)
  if isWindows == nil then
    isWindows = IS_WINDOWS
  end
  local parts = {}
  for i, arg in ipairs(argv) do
    parts[i] = quoted(arg, isWindows)
  end
  local line = table.concat(parts, " ") .. " > " .. quoted(logPath, isWindows) .. " 2>&1"
  return isWindows and '"' .. line .. '"' or line
end

-- Lua 5.1 returns the raw status (a POSIX exit code sits in the high byte); 5.4 returns ok, "exit"|"signal", code.
local function exitCode(ok, how, code)
  if how == "exit" or how == "signal" then
    return code
  elseif type(ok) == "number" then
    return ok >= SIGNAL_STATUS_UNIT and math.floor(ok / SIGNAL_STATUS_UNIT) or ok
  end
  return ok == true and 0 or 1
end

-- Runs argv and returns its exit code; its output lands in logPath.
function M.run(argv, logPath)
  return exitCode(os.execute(M.command(argv, logPath)))
end

return M

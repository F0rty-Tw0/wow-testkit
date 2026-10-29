-- Filesystem access for the kit. Uses the __tk_fs bridge when tools/run51.py provides it,
-- else shell fallbacks (cmd.exe on Windows, POSIX tools elsewhere).
local M = {}

local Proc = require("proc")

local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local EACCES = 13
-- Localized: addon code may assign a global named io or os. The tables, not their functions, so a test can still
-- swap a function such as os.rename.
local io, os = io, os

local function host()
  return rawget(_G, "__tk_fs")
end

-- Why native cannot go inside double quotes for the shell fallbacks, or nil. sh is as strict as Proc.refusal. Inside
-- cmd's quotes only a double quote or a line break ends the argument and %VAR% still expands; ! and ^ stay literal
-- unless cmd runs with delayed expansion (registry DelayedExpansion=1), where !VAR! expands inside quotes too. That only
-- changes the path text, so the call fails to find the folder instead of running anything. By default a folder such as
-- !BugGrabber passes. A final backslash only matters to programs that parse their own command line; mkdir and dir do
-- not.
local function refusal(native)
  if not IS_WINDOWS then
    return Proc.refusal(native, false)
  elseif native:find('"', 1, true) then
    return "contains a double quote"
  elseif native:find("[\r\n]") or native:find("\0", 1, true) then
    return "contains a line break"
  elseif native:find("%", 1, true) then
    return "contains %, which windows cmd expands inside quotes"
  end
  return nil
end

-- path inside double quotes for the shell fallbacks. Raises when the shell would still expand something inside the
-- quotes ($(...) on sh, %VAR% on cmd), since paths here can come from an addon's name.
local function shellPath(path)
  local native = IS_WINDOWS and path:gsub("/", "\\") or path
  local reason = refusal(native)
  if reason then
    error("fs: path " .. reason .. ": " .. path:gsub("%c", "?"), 0)
  end
  return '"' .. native .. '"'
end

function M.readFile(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err
  end
  local text = file:read("*a")
  file:close()
  return text
end

function M.writeFile(path, text)
  local file = assert(io.open(path, "wb"))
  assert(file:write(text))
  assert(file:close())
end

-- Renaming a path onto itself succeeds (or is refused with EACCES) only when it exists.
local function renameProbe(path)
  local ok, _, code = os.rename(path, path)
  return ok ~= nil or code == EACCES
end

-- Moves the file from onto to, replacing a file already there: atomically through the bridge (Python's os.replace).
-- Without it, Windows' rename refuses an existing target, so there that target is removed first and the rename
-- retried: a crash between the two leaves the data only in from. Elsewhere os.rename already replaces.
function M.rename(from, to)
  local bridge = host()
  if bridge then
    bridge.replace(from, to)

    return
  end
  local ok, err = os.rename(from, to)
  local refused = not ok and IS_WINDOWS
  local stale = refused and M.exists(to)
  if stale then
    assert(os.remove(to))
    ok, err = os.rename(from, to)
  end
  assert(ok, err)
end

-- A file that opens exists, and so does one whose open is refused with EACCES (a file that cannot be read, or a
-- directory on Windows); the rename probe covers the rest. Opening first keeps a read-only mount working, where the
-- rename fails with EROFS.
function M.exists(path)
  local bridge = host()
  if bridge then
    return bridge.exists(path)
  end
  local file, _, code = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return code == EACCES or renameProbe(path)
end

function M.isdir(path)
  local bridge = host()
  if bridge then
    return bridge.isdir(path)
  end
  return renameProbe(path .. "/")
end

function M.mkdirp(path)
  local bridge = host()
  if bridge then
    bridge.mkdirp(path)
  elseif not M.isdir(path) then
    os.execute((IS_WINDOWS and "mkdir " or "mkdir -p ") .. shellPath(path))
  end
end

-- Creates the one directory path: true when this call created it, false when it already existed; raises on any
-- other failure. Atomic, so concurrent processes can claim unique directories with it. A missing parent raises on
-- the bridge and on POSIX; Windows cmd creates it.
function M.mkdir(path)
  local bridge = host()
  if bridge then
    return bridge.mkdir(path)
  end
  local result = os.execute("mkdir " .. shellPath(path) .. (IS_WINDOWS and " 2>nul" or " 2>/dev/null"))
  if result == 0 or result == true then
    return true
  end
  if not M.isdir(path) then
    error("fs.mkdir: cannot create " .. path, 2)
  end
  return false
end

function M.list(dir)
  local bridge = host()
  if bridge then
    return bridge.list(dir)
  end
  local names = {}
  local pipe = assert(io.popen((IS_WINDOWS and "dir /b " or "ls -1 ") .. shellPath(dir) .. " 2>" .. (IS_WINDOWS and "nul" or "/dev/null")))
  for name in pipe:lines() do
    names[#names + 1] = name
  end
  pipe:close()
  table.sort(names)
  return names
end

return M

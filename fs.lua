-- Filesystem access for the kit. Uses the __tk_fs bridge when tools/run51.py provides it,
-- else shell fallbacks (cmd.exe on Windows, POSIX tools elsewhere).
local M = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local EACCES = 13
-- Localized: addon code may assign a global named io.
local ioOpen, ioPopen = io.open, io.popen

local function host()
  return rawget(_G, "__tk_fs")
end

local function shellPath(path)
  return '"' .. (IS_WINDOWS and path:gsub("/", "\\") or path) .. '"'
end

function M.readFile(path)
  local file, err = ioOpen(path, "rb")
  if not file then
    return nil, err
  end
  local text = file:read("*a")
  file:close()
  return text
end

function M.writeFile(path, text)
  local file = assert(ioOpen(path, "wb"))
  assert(file:write(text))
  assert(file:close())
end

-- Renaming a path onto itself succeeds (or is refused with EACCES) only when it exists.
local function renameProbe(path)
  local ok, _, code = os.rename(path, path)
  return ok ~= nil or code == EACCES
end

function M.exists(path)
  local bridge = host()
  if bridge then
    return bridge.exists(path)
  end
  return renameProbe(path)
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
  local pipe = assert(ioPopen((IS_WINDOWS and "dir /b " or "ls -1 ") .. shellPath(dir) .. " 2>" .. (IS_WINDOWS and "nul" or "/dev/null")))
  for name in pipe:lines() do
    names[#names + 1] = name
  end
  pipe:close()
  table.sort(names)
  return names
end

return M

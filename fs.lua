-- Filesystem access for the kit. Uses the __tk_fs bridge when tools/run51.py provides it,
-- else shell fallbacks (cmd.exe on Windows, POSIX tools elsewhere).
local M = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local EACCES = 13

local function host()
  return rawget(_G, "__tk_fs")
end

local function shellPath(path)
  return '"' .. (IS_WINDOWS and path:gsub("/", "\\") or path) .. '"'
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
  file:write(text)
  file:close()
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

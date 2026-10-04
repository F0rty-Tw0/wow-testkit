-- Kit test runner for any Lua (5.1 or 5.4).
--   lua tests/run.lua <test.lua>                    -> runs the file, calls the function it returns, prints PASS/FAIL
--   lua tests/run.lua --script <file.lua> [args...] -> runs the file with `...` = args, exits with its returned number
-- tools/run51.py hosts this same file on lupa's Lua 5.1.

local unpack = rawget(table, "unpack") or unpack

local SELF = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local ROOT = SELF:gsub("/?tests/run%.lua$", "")
if ROOT == "" then
  ROOT = "."
end
package.path = ROOT .. "/?.lua;" .. ROOT .. "/?/init.lua;" .. package.path

local function runProtected(fn)
  local ok, err = xpcall(fn, debug.traceback)
  return ok, err
end

local function runTest(path)
  local ok, err = runProtected(function()
    local testFn = assert(loadfile(path))()
    if type(testFn) == "function" then
      testFn()
    end
  end)
  if ok then
    print("PASS " .. path)
    return 0
  end
  print("FAIL " .. path)
  io.stdout:flush()
  io.stderr:write(tostring(err), "\n")
  return 1
end

local function runScript(path, ...)
  local args, count = { ... }, select("#", ...)
  -- _G: in Lua 5.1 every vararg function has an implicit local named `arg`.
  _G.arg = { [0] = path, unpack(args, 1, count) }
  local code
  local ok, err = runProtected(function()
    code = assert(loadfile(path))(unpack(args, 1, count))
  end)
  if not ok then
    io.stderr:write(tostring(err), "\n")
    return 1
  end
  return type(code) == "number" and code or 0
end

local function main(first, ...)
  if first == "--script" then
    return runScript(...)
  end
  assert(first, "usage: lua tests/run.lua <test.lua> | --script <file.lua> [args...]")
  return runTest(first)
end

os.exit(main(...))

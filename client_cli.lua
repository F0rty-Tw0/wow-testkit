-- `tk client extract|status [args]`: runs tools/tk_client.py (python -m tools.client) through Proc, then echoes its log.
-- The reader and its Pillow, fontTools and lupa dependencies live in Python; the kit only reads the files it writes.
local M = {}

local Home = require("home")
local Proc = require("proc")
local fs = require("fs")

local EXIT_USAGE = 2
local LOG_FILE = "/.tk-client.log"
local VERBS = { extract = true, status = true }
-- Every kit module loads from the same package.path root as this file.
local KIT_ROOT = debug.getinfo(1, "S").source:match("^@(.*)[/\\]client_cli%.lua$") or "."

M.USAGE = "usage: tk client extract|status [--flavor F] [extract: --what KINDS] [--install DIR] [--listfile FILE]\n"

-- Runs argv, logging its output to logPath; returns its exit code. Tests replace this field.
M.exec = Proc.run

-- { python, tk_client.py, args... } for args (verb first), or nil plus the usage message.
function M.argv(args)
  if not VERBS[args[1]] then
    return nil, M.USAGE
  end
  local argv = { os.getenv("TK_PYTHON") or "python", KIT_ROOT .. "/tools/tk_client.py" }
  for _, arg in ipairs(args) do
    argv[#argv + 1] = arg
  end
  return argv
end

-- The log path for a run: inside the testkit home, which the extractor creates when it does not exist yet.
local function logPath()
  fs.mkdirp(Home.dir())
  return Home.dir() .. LOG_FILE
end

-- Runs the verb; its output goes through write. log: where the run logs (default: inside the testkit home). Returns
-- the exit code of the python run, 2 on a usage error.
function M.run(args, write, log)
  local argv, usage = M.argv(args)
  if not argv then
    write(usage)
    return EXIT_USAGE
  end
  local ok, path = pcall(function()
    return log or logPath()
  end)
  if not ok then
    write("tk client: " .. tostring(path) .. "\n")
    return EXIT_USAGE
  end
  log = path
  fs.writeFile(log, "")
  local ran, code = pcall(M.exec, argv, log)
  write(fs.readFile(log) or "")
  if not ran then
    write("tk client: failed: " .. tostring(code) .. "\n")
    return 1
  end
  return code
end

return M

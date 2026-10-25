-- tk client: runs tools/tk_client.py (python -m tools.client) through Proc and echoes its log.
local A = require("assert")
local Cli = require("bin.tk")
local ClientCli = require("client_cli")
local Proc = require("proc")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local PYTHON = Proc.python()

local function test_argv_runs_the_python_entry_with_the_verb_and_its_args()
  local argv = assert(ClientCli.argv({ "extract", "--flavor", "forever" }))
  A.eq(argv[1], PYTHON)
  A.eq(argv[2]:sub(-#"tools/tk_client.py"), "tools/tk_client.py")
  A.same({ argv[3], argv[4], argv[5] }, { "extract", "--flavor", "forever" })
  A.eq(#argv, 5)
end

local function test_argv_accepts_status()
  A.eq(assert(ClientCli.argv({ "status" }))[3], "status")
end

local function test_unknown_verb_is_nil_with_a_usage_message()
  local argv, err = ClientCli.argv({ "bogus" })
  A.eq(argv, nil)
  A.contains(err, "tk client extract|status")
  local none, noneErr = ClientCli.argv({})
  A.eq(none, nil)
  A.contains(noneErr, "tk client extract|status")
end

local function test_main_exits_2_on_an_unknown_verb()
  local out = {}
  local code = Cli.main({ "client", "bogus" }, function(text)
    out[#out + 1] = text
  end)
  A.eq(code, 2)
  A.contains(table.concat(out), "tk client")
end

local function test_run_echoes_the_log_and_returns_the_exit_code()
  local log = Tmp.dir("clientcli") .. "/client.log"
  local seen, saved = nil, ClientCli.exec
  ClientCli.exec = function(argv, logPath)
    seen = argv
    fs.writeFile(logPath, "extracted retail 1\n")
    return 3
  end
  local out = {}
  local ok, code = pcall(ClientCli.run, { "status" }, function(text)
    out[#out + 1] = text
  end, log)
  ClientCli.exec = saved
  A.eq(ok, true)
  A.eq(code, 3)
  A.eq(seen[3], "status")
  A.eq(table.concat(out), "extracted retail 1\n")
end

local function test_run_reports_an_exec_that_raises_and_exits_1()
  local saved = ClientCli.exec
  ClientCli.exec = function()
    error("no python", 0)
  end
  local out = {}
  local ok, code = pcall(ClientCli.run, { "status" }, function(text)
    out[#out + 1] = text
  end, Tmp.dir("clientcli") .. "/client.log")
  ClientCli.exec = saved
  A.eq(ok, true)
  A.eq(code, 1)
  A.contains(table.concat(out), "no python")
end

return function()
  test_argv_runs_the_python_entry_with_the_verb_and_its_args()
  test_argv_accepts_status()
  test_unknown_verb_is_nil_with_a_usage_message()
  test_main_exits_2_on_an_unknown_verb()
  test_run_echoes_the_log_and_returns_the_exit_code()
  test_run_reports_an_exec_that_raises_and_exits_1()
end

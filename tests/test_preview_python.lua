-- The python Preview.run and tk client start: TK_PYTHON, else `python`, else `python3` when only that is on PATH.
local A = require("assert")
local ClientCli = require("client_cli")
local P = require("tests.helpers.preview")
local Proc = require("proc")
local Tmp = require("tests.helpers.tmp")

-- With TK_PYTHON set it wins over whatever the lookup says; the expectation is that name, else the fallback.
local EXPECTED_WITHOUT_PYTHON = os.getenv("TK_PYTHON") or "python3"

-- Runs fn with Proc.hasCommand answering false, whatever fn does.
local function withoutPython(fn)
  local saved = Proc.hasCommand
  Proc.hasCommand = function()
    return false
  end
  local ok, err = pcall(fn)
  Proc.hasCommand = saved
  if not ok then
    error(err, 0)
  end
end

local function test_resolve_and_png_steps_use_python3_when_python_is_not_on_the_path()
  withoutPython(function()
    P.withExec(nil, function(calls)
      local out = Tmp.dir("previewout")
      P.run({ addonDir = P.tempAddon(P.FRAME_ADDON), out = out, png = out .. "/shot.png" })
      A.eq(#calls, 2)
      A.same({ calls[1][1], calls[2][1] }, { EXPECTED_WITHOUT_PYTHON, EXPECTED_WITHOUT_PYTHON })
    end)
  end)
end

local function test_tk_client_uses_python3_when_python_is_not_on_the_path()
  withoutPython(function()
    A.eq(assert(ClientCli.argv({ "status" }))[1], EXPECTED_WITHOUT_PYTHON)
  end)
end

return function()
  test_resolve_and_png_steps_use_python3_when_python_is_not_on_the_path()
  test_tk_client_uses_python3_when_python_is_not_on_the_path()
end

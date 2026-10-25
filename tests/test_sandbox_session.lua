-- The session's /run as the client runs it: code typed into the console reads _G as the client's, so the lupa hosts'
-- bridges into Python are not among its globals, and a precompiled chunk is refused as the client refuses it. Client
-- fidelity only: addon code is trusted, and this is not a security boundary.
local A = require("assert")
local H = require("tests.helpers.session")

local function lastLine(sess)
  local lines = sess:call("console", { since = 0 }).lines
  return lines[#lines]
end

-- Under tools/run51.py the bridge is there to hide; under a plain lua5.1 (CI) there is none, and /run still sees nil.
local function test_run_reads_no_host_bridge_global()
  H.withSession(nil, function(sess)
    sess:call("slash", { text = "/run print(type(python), type(__tk_fs), type(rawget(_G, '__tk_fs')), type(getfenv(0).__tk_fs))" })
    A.same({ lastLine(sess).kind, lastLine(sess).text }, { "print", "nil nil nil nil" })
  end)
end

local function test_run_refuses_a_precompiled_chunk()
  H.withSession(nil, function(sess)
    _G.SandboxRan = nil
    local bytecode = string.dump(function()
      _G.SandboxRan = true
    end)
    sess:call("slash", { text = "/run " .. bytecode })
    A.same({ lastLine(sess).kind, lastLine(sess).text }, { "error", "the chunk is precompiled bytecode, which is never run" })
    A.eq(rawget(_G, "SandboxRan"), nil)
  end)
end

return function()
  test_run_reads_no_host_bridge_global()
  test_run_refuses_a_precompiled_chunk()
end

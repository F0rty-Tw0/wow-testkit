-- The session's /run sandbox: code typed into the console sees none of the lupa hosts' bridges into Python, and a
-- precompiled chunk is refused, never run.
local A = require("assert")
local H = require("tests.helpers.session")

local function lastLine(sess)
  local lines = sess:call("console", { since = 0 }).lines
  return lines[#lines]
end

local function test_run_sees_no_python_bridge()
  A.truthy(rawget(_G, "__tk_fs"), "tools/run51.py installs the bridge this test hides")
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
  test_run_sees_no_python_bridge()
  test_run_refuses_a_precompiled_chunk()
end

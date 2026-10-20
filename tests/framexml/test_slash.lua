-- SlashCmdList and w:slash: dispatching a typed slash command to the addon's handler.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_slash_calls_handler_with_args()
  withFrameXML("retail", function(w)
    local got
    _G.SlashCmdList.FOO = function(args)
      got = args
    end
    w:setGlobal("SLASH_FOO1", "/foo")
    A.eq(w:slash("/foo bar"), true)
    A.eq(got, "bar")
  end)
end

local function test_slash_matches_any_numbered_alias_case_insensitively()
  withFrameXML("vanilla", function(w)
    local calls = 0
    _G.SlashCmdList.FOO = function()
      calls = calls + 1
    end
    w:setGlobal("SLASH_FOO1", "/foo")
    w:setGlobal("SLASH_FOO2", "/F")
    w:slash("/f")
    A.eq(calls, 1)
  end)
end

local function test_slash_handler_runs_in_addon_context()
  withFrameXML("retail", function(w)
    local context
    _G.SlashCmdList.FOO = function()
      context = w:context()
    end
    w:setGlobal("SLASH_FOO1", "/foo")
    w:slash("/foo")
    A.eq(context, "addon")
  end)
end

local function test_unknown_slash_returns_false()
  withFrameXML("retail", function(w)
    A.eq(w:slash("/nope"), false)
  end)
end

return function()
  test_slash_calls_handler_with_args()
  test_slash_matches_any_numbered_alias_case_insensitively()
  test_slash_handler_runs_in_addon_context()
  test_unknown_slash_returns_false()
end

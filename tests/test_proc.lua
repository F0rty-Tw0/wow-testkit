-- Proc: the one place besides fs.lua that spawns a process; builds a quoted shell command and refuses arguments the
-- shell would reinterpret.
local A = require("assert")
local Proc = require("proc")
local Tmp = require("tests.helpers.tmp")

local function test_command_quotes_each_argument_and_redirects()
  A.eq(Proc.command({ "python", "a b.py" }, "log.txt", false), '"python" "a b.py" > "log.txt" 2>&1')
end

local function test_command_on_windows_is_wrapped_in_one_more_pair_of_quotes()
  local line = Proc.command({ "python", "a b.py" }, "log.txt", true)
  A.eq(line:sub(1, 1), '"')
  A.eq(line:sub(-1), '"')
  A.truthy(line:find('"python" "a b.py" > "log.txt" 2>&1"', 1, true))
end

-- cmd.exe looks in the current directory before PATH; an addon folder holding python.bat would otherwise run.
local function test_command_on_windows_stops_cmd_searching_the_current_directory()
  local line = Proc.command({ "python" }, "log.txt", true)
  A.eq(line, '"set "NoDefaultCurrentDirectoryInExePath=1" & "python" > "log.txt" 2>&1"')
  A.eq(Proc.command({ "python" }, "log.txt", false):find("NoDefaultCurrentDirectoryInExePath", 1, true), nil)
end

local function test_argument_with_a_double_quote_raises()
  A.errors(function()
    Proc.command({ "python", 'a" & calc & "b' }, "log.txt", false)
  end, "double quote")
end

local function test_log_path_is_checked_like_an_argument()
  A.errors(function()
    Proc.command({ "python" }, 'log" & calc & "', false)
  end, "double quote")
end

local function test_newline_in_an_argument_raises()
  A.errors(function()
    Proc.command({ "python", "a\nb" }, "log.txt", false)
  end, "line break")
  A.errors(function()
    Proc.command({ "python", "a\rb" }, "log.txt", true)
  end, "line break")
end

local function test_windows_refuses_percent_caret_bang_and_a_trailing_backslash()
  for _, arg in ipairs({ "%PATH%", "a^b", "a!b", "C:\\dir\\" }) do
    A.errors(function()
      Proc.command({ "python", arg }, "log.txt", true)
    end, "windows")
  end
end

local function test_posix_refuses_dollar_backtick_and_backslash()
  for _, arg in ipairs({ "$HOME", "`id`", "a\\b" }) do
    A.errors(function()
      Proc.command({ "python", arg }, "log.txt", false)
    end, "posix")
  end
end

local function test_other_shell_characters_stay_literal_inside_the_quotes()
  A.eq(Proc.command({ "a&b", "c|d", "e<f>g", "100%" }, "log.txt", false), '"a&b" "c|d" "e<f>g" "100%" > "log.txt" 2>&1')
end

local function test_run_returns_the_exit_code()
  local log = Tmp.dir("proc") .. "/run.log"
  A.eq(Proc.run({ "python", "-c", "import sys; sys.exit(3)" }, log), 3)
  A.eq(Proc.run({ "python", "-c", "pass" }, log), 0)
end

return function()
  test_command_quotes_each_argument_and_redirects()
  test_command_on_windows_is_wrapped_in_one_more_pair_of_quotes()
  test_command_on_windows_stops_cmd_searching_the_current_directory()
  test_argument_with_a_double_quote_raises()
  test_log_path_is_checked_like_an_argument()
  test_newline_in_an_argument_raises()
  test_windows_refuses_percent_caret_bang_and_a_trailing_backslash()
  test_posix_refuses_dollar_backtick_and_backslash()
  test_other_shell_characters_stay_literal_inside_the_quotes()
  test_run_returns_the_exit_code()
end

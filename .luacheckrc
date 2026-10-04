-- .luacheckrc for wow-testkit (offline WoW addon test kit)
-- Targets Lua 5.1 (WoW runtime)

std = "lua51"
max_line_length = false -- StyLua handles formatting; luacheck handles semantics
cache = true
jobs = 4

exclude_files = {
  ".luacheckrc",
  "api/", -- generated
}

ignore = {
  "212/self", -- unused 'self' in method definitions
}

-- Runners set `arg` for --script mode; fixtures read it.
files["tests/**/*.lua"] = {
  globals = { "arg" },
}

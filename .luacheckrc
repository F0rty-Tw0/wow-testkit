-- .luacheckrc for wow-testkit (offline WoW addon test kit)
-- Targets Lua 5.1 (WoW runtime)

std = "lua51"
max_line_length = false -- StyLua handles formatting; luacheck handles semantics
cache = true
jobs = 4

exclude_files = {
  ".luacheckrc",
  "api/", -- generated
  "tests/fixtures/docs_bad/", -- deliberately invalid Lua
}

ignore = {
  "212/self", -- unused 'self' in method definitions
}

-- Runners set `arg` for --script mode; fixtures read it.
files["tests/**/*.lua"] = {
  globals = { "arg" },
}

-- Synthetic API documentation files run inside the docs loader's sandbox.
files["tests/fixtures/docs*/*.lua"] = {
  read_globals = { "APIDocumentation", "Enum", "Constants" },
}

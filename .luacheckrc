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

-- Addon loader fixture: its global write is the behavior under test.
files["tests/fixtures/addons/Mini/C.lua"] = {
  globals = { "MiniGlobal" },
}

-- Scenario fixture addon: written like a real addon against the WoW globals the world installs.
files["tests/fixtures/addons/Hover/*.lua"] = {
  read_globals = { "CreateFrame", "Enum", "GameTooltip", "HoverDB", "TooltipDataProcessor", "UnitName" },
}

-- Canary fixture addons (canaries/<layer>/<name>/<variant>/): written like real addons against the world's
-- WoW globals; the directive canaries' global writes are the behavior under test.
files["canaries/*/*/*/*.lua"] = {
  globals = { "CanaryForeverFile", "CanaryMainlineOnly" },
  read_globals = { "C_PlayerInfo", "CreateFrame", "UIParent", "UnitHealth", "UnitName" },
}

-- Synthetic API documentation files run inside the docs loader's sandbox.
files["tests/fixtures/docs*/*.lua"] = {
  read_globals = { "APIDocumentation", "Enum", "Constants" },
}

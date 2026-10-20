-- Callsite.level: the error() level of the first caller outside the kit's widget layer.
local A = require("assert")
local Callsite = require("ui.callsite")

local CALLSITE_SOURCE = debug.getinfo(Callsite.level, "S").source
local KIT_ROOT = CALLSITE_SOURCE:match("^@(.*)ui[/\\]callsite%.lua$")

-- A function in a chunk named chunkName that calls raise() from the chunk's line 3.
local function caller(chunkName, raise)
  local chunk = assert(loadstring("local raise = ...\nreturn function()\n  raise()\nend", "@" .. chunkName))
  return chunk(raise)
end

local function messageFrom(fn)
  local ok, err = pcall(fn)
  A.eq(ok, false)
  return tostring(err)
end

local function raise()
  error("boom", Callsite.level())
end

local function test_a_kit_file_is_skipped()
  local kitFile = caller(KIT_ROOT .. "ui/callsite.lua", raise)
  local message = messageFrom(function()
    kitFile()
  end)
  A.truthy(message:find("test_callsite%.lua:%d+: boom"), message)
end

local function test_a_chunk_named_like_a_missing_kit_file_is_not_skipped()
  for _, name in ipairs({ "ui/no_such_file.lua", "world_no_such_file.lua" }) do
    local consumer = caller(KIT_ROOT .. name, raise)
    local message = messageFrom(function()
      consumer()
    end)
    A.truthy(message:find(name .. ":3: boom", 1, true), message)
  end
end

-- Loaded through a bare "?.lua" package.path (cwd = kit root), the kit's sources have no directory prefix.
local function test_an_empty_kit_root_still_names_a_consumer_ui_file()
  local file = assert(io.open(CALLSITE_SOURCE:sub(2), "rb"))
  local text = file:read("*a")
  file:close()
  local relative = assert(loadstring(text, "@ui/callsite.lua"))()
  local consumer = caller("ui/x.lua", function()
    error("boom", relative.level())
  end)
  local message = messageFrom(function()
    consumer()
  end)
  A.truthy(message:find("^ui/x%.lua:3: boom"), message)
end

return function()
  test_a_kit_file_is_skipped()
  test_a_chunk_named_like_a_missing_kit_file_is_not_skipped()
  test_an_empty_kit_root_still_names_a_consumer_ui_file()
end

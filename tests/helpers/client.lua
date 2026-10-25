-- Mini client extracts for tests: files are written from strings, never copied from a Blizzard file.
local Client = require("client")
local fs = require("fs")

local M = {}

local function manifestText(flavor, build)
  return string.format(
    'return { product = "wow", flavor = "%s", build = "%s", version = "12.1.5.%s", locales = { "enUS" }, extracted = {} }',
    flavor,
    build,
    build
  )
end

-- Writes <root>/client/<flavor>/<build>/manifest.lua plus files[relpath] = text, and returns the extract Client.load
-- reads back from it (the table Client.find answers for that build).
function M.extract(root, flavor, build, files)
  local dir = root .. "/client/" .. flavor .. "/" .. build
  fs.mkdirp(dir)
  fs.writeFile(dir .. "/manifest.lua", manifestText(flavor, build))
  for relpath, text in pairs(files) do
    local parent = relpath:match("^(.*)/[^/]*$")
    if parent then
      fs.mkdirp(dir .. "/" .. parent)
    end
    fs.writeFile(dir .. "/" .. relpath, text)
  end
  return Client.load(dir, flavor)
end

-- A getenv for Home.dir that sees only TESTKIT_HOME = root.
function M.getenv(root)
  return function(name)
    return name == "TESTKIT_HOME" and root or nil
  end
end

return M

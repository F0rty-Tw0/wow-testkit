-- XML loader test helpers: an addon folder written to a temp dir, loaded in a retail world with the stage-1 FrameXML fakes.
local Addon = require("addon")
local FrameXML = require("tests.helpers.framexml")
local Tmp = require("tests.helpers.tmp")
local Xml = require("ui.xml")
local fs = require("fs")

local M = {}

-- files: { [path relative to the addon root] = text }. Runs fn(w, ctx) in a world whose screen is 1000x800.
function M.withXml(files, fn)
  local root = Tmp.dir("xml") .. "/XmlT"
  fs.mkdirp(root)
  for relative, text in pairs(files) do
    fs.mkdirp((root .. "/" .. relative):match("^(.*)/[^/]*$"))
    fs.writeFile(root .. "/" .. relative, text)
  end
  FrameXML.withFrameXML("retail", function(w)
    fn(w, Addon.context(w, "XmlT", root))
  end, { screen = { width = 1000, height = 800 } })
end

function M.load(w, ctx, relative)
  return Xml.loadFile(w, relative, ctx)
end

return M

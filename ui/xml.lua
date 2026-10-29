-- XML file loader: parses an addon's XML file and walks its root <Ui> in document order. Include recurses (an included
-- .lua file runs like a Script), Script runs a Lua file or inline source, every other element goes to Xml.element.
local M = {}

local XmlBuild = require("ui.xml_build")
local XmlParse = require("ui.xml_parse")

-- Element modules register their handlers and finishers in XmlBuild when required; the order fixes the finishers'.
require("ui.xml_layout")
require("ui.xml_widgets")
require("ui.xml_animations")
require("ui.xml_scripts")

-- Path with "\" turned into "/" and "." and ".." segments resolved, so one file never has two spellings.
local function clean(path)
  local parts = {}
  for part in path:gsub("\\", "/"):gmatch("[^/]+") do
    if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

-- `relative` resolved against the folder of the including file.
local function join(includer, relative)
  local dir = includer:match("^(.*)/[^/]*$")
  return clean((dir and dir .. "/" or "") .. relative)
end

-- source: assumed (row BU4) a `file=` path is tried relative to the including XML file's folder first, then, when no
-- such file exists, relative to the addon root: Blizzard's own XML names root-relative files. Returns the path to load
-- (the folder-relative one when neither exists, so the missing-file report names it).
local function resolve(ctx, includer, relative)
  local path = join(includer, relative)
  if ctx.exists and not ctx.exists(path) then
    local fromRoot = clean(relative)
    return ctx.exists(fromRoot) and fromRoot or path
  end
  return path
end

-- Registers the virtual element `node` as template `name` (a FontString or Texture too): CreateFrame's template list and
-- `inherits` find it there. origin is the session of the file that holds it.
M.registerVirtual = XmlBuild.registerVirtual

-- Builds one element of the root <Ui>: a frame, or a virtual region template. Every other element is reported and
-- skipped. An error in one element is reported (XmlBuild.guard) and the next element still builds.
function M.element(w, node, session)
  if XmlBuild.isRegion(node) and node.attrs.virtual == "true" then
    XmlBuild.region(w, node, nil, session)
  else
    XmlBuild.frame(w, node, nil, session)
  end
end

local loadInto

local function include(w, node, ctx, file, loading)
  local target = resolve(ctx, file.path, node.attrs.file)
  if target:lower():match("%.lua$") then
    ctx.runFile(target, file.path)
  elseif loading[target:lower()] then
    ctx.report[#ctx.report + 1] = target .. ": include cycle ignored"
  else
    loadInto(w, target, ctx, loading, file.path)
  end
end

-- source: wiki XML/Script, "Executed when reached by the XML parser, going from top to bottom."
local function walk(w, root, ctx, file, loading, session)
  for _, node in ipairs(root.children) do
    if node.tag == "include" and node.attrs.file then
      include(w, node, ctx, file, loading)
    elseif node.tag == "script" and node.attrs.file then
      ctx.runFile(resolve(ctx, file.path, node.attrs.file), file.path)
    elseif node.tag == "script" then
      ctx.runSource(node.text, "addon:" .. ctx.name .. "/" .. file.path, node.textLine)
    else
      XmlBuild.guard(w, session, node.line, M.element, w, node, session)
    end
  end
end

-- listedBy: the XML file whose <Include> names path, nil when the TOC lists it.
loadInto = function(w, path, ctx, loading, listedBy)
  local text = ctx.readFile(path, listedBy)
  if not text then
    ctx.report[#ctx.report + 1] = path .. ": cannot read XML file"
    return false, "cannot read " .. path
  end
  local root, message = XmlParse.parse(text)
  if not root then
    w:reportError("addon:" .. ctx.name .. "/" .. path .. ": " .. message)
    return false, message
  end
  local file = { path = path, seen = {} }
  -- One session per file, so an anchor may name a frame of a later root element; XmlBuild.finish reports what is left.
  local session = XmlBuild.session(ctx, file)
  loading[path:lower()] = true
  if root.tag == "ui" then
    walk(w, root, ctx, file, loading, session)
  else
    XmlBuild.guard(w, session, root.line, M.element, w, root, session)
  end
  XmlBuild.finish(w, session)
  loading[path:lower()] = nil
  return true
end

-- Loads the XML file at `path` (relative to the addon root, "/" or "\") into the world as addonCtx's addon. True, or
-- false and the reason when the file cannot be read or parsed (the error is reported on the way).
function M.loadFile(w, path, addonCtx)
  return loadInto(w, clean(path), addonCtx, {})
end

return M

-- XML file loader: parses an addon's XML file and walks its root <Ui> in document order. Include recurses, Script runs
-- a Lua file or inline source, every other element goes to Xml.element.
local M = {}

local XmlParse = require("ui.xml_parse")

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

-- Reports `what` for this file once per key.
local function reportOnce(ctx, file, key, what)
  if not file.seen[key] then
    file.seen[key] = true
    ctx.report[#ctx.report + 1] = file.path .. ": " .. what
  end
end

-- Builds one element of the root <Ui>. Frames come in a later task; for now every element is reported and skipped.
function M.element(_, node, ctx, session)
  reportOnce(ctx, session.file, "tag:" .. node.tag, "unsupported XML <" .. node.rawTag .. "> ignored")
end

local loadInto

local function include(w, node, ctx, file, loading)
  local target = join(file.path, node.attrs.file)
  if loading[target] then
    ctx.report[#ctx.report + 1] = target .. ": include cycle ignored"
  else
    loadInto(w, target, ctx, loading)
  end
end

-- source: wiki XML/Script, "Executed when reached by the XML parser, going from top to bottom."
local function walk(w, root, ctx, file, loading)
  for _, node in ipairs(root.children) do
    if node.tag == "include" and node.attrs.file then
      include(w, node, ctx, file, loading)
    elseif node.tag == "script" and node.attrs.file then
      ctx.runFile(join(file.path, node.attrs.file))
    elseif node.tag == "script" then
      ctx.runSource(node.text, "addon:" .. ctx.name .. "/" .. file.path, node.textLine)
    else
      M.element(w, node, ctx, { ctx = ctx, file = file, anchors = {} })
    end
  end
end

loadInto = function(w, path, ctx, loading)
  local text = ctx.readFile(path)
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
  loading[path] = true
  if root.tag == "ui" then
    walk(w, root, ctx, file, loading)
  else
    M.element(w, root, ctx, { ctx = ctx, file = file, anchors = {} })
  end
  loading[path] = nil
  return true
end

-- Loads the XML file at `path` (relative to the addon root, "/" or "\") into the world as addonCtx's addon. True, or
-- false and the reason when the file cannot be read or parsed (the error is reported on the way).
function M.loadFile(w, path, addonCtx)
  return loadInto(w, clean(path), addonCtx, {})
end

return M

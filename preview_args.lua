-- `tk preview` arguments: `<addon-dir> [--flavor F] [--scenario FILE] [--size WxH] [--out DIR] [--png FILE]` parsed
-- into the options Preview.run takes.
local M = {}

local Flavors = require("tools.flavors")

local MAX_SIDE = 16384
local PATH_FLAGS = { ["--scenario"] = "scenario", ["--out"] = "out", ["--png"] = "png" }

local function slashes(path)
  return (path:gsub("\\", "/"):gsub("(.)/+$", "%1"))
end

-- { width, height } from "WxH" (both in 1..MAX_SIDE), or nil.
local function parseSize(text)
  local width, height = text:match("^(%d+)x(%d+)$")
  width, height = tonumber(width), tonumber(height)
  if width and height and width >= 1 and height >= 1 and width <= MAX_SIDE and height <= MAX_SIDE then
    return { width = width, height = height }
  end
  return nil
end

-- Sets opts for one preview flag from value; returns an error message or nil.
local function setFlag(opts, flag, value)
  if flag == "--flavor" then
    if not pcall(Flavors.get, value) then
      return "unknown flavor '" .. value .. "'; flavors: " .. table.concat(Flavors.list, ", ")
    end
    opts.flavor = value
  elseif flag == "--size" then
    opts.size = parseSize(value)
    if not opts.size then
      return "--size needs WxH with both sides from 1 to " .. MAX_SIDE .. ", got '" .. value .. "'"
    end
  else
    opts[PATH_FLAGS[flag]] = slashes(value)
  end
  return nil
end

-- { addonDir, flavor?, scenario?, size?, out?, png? } from argv[2..], or nil plus a message.
function M.parse(argv)
  local dir = argv[2]
  if not dir or dir:sub(1, 2) == "--" then
    return nil, "preview needs an addon directory"
  end
  local opts, i = { addonDir = slashes(dir) }, 3
  while i <= #argv do
    local flag = argv[i]
    if flag ~= "--flavor" and flag ~= "--size" and not PATH_FLAGS[flag] then
      return nil, "unknown option '" .. flag .. "'"
    end
    i = i + 1
    if not argv[i] then
      return nil, flag .. " needs a value"
    end
    local err = setFlag(opts, flag, argv[i])
    if err then
      return nil, err
    end
    i = i + 1
  end
  return opts
end

return M

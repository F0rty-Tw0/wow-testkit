-- Locates the file behind a snapshot asset on disk: an addon file or a file of the client extract. A port of
-- tools/preview_assets.py `locate` without the lazy decode and the stand-ins; tests/fixtures/session_assets/cases.json
-- pins the two together. The walk follows only names `fs.list` returns and refuses unsafe parts, so it never leaves its
-- root; the Python host re-checks containment (realpath) before it serves a hit.
local Client = require("client")
local fs = require("fs")

local M = {}

local IMAGE_EXTENSIONS = { ".png", ".jpg", ".tga", ".blp" } -- probe order when a path has no extension
local IS_IMAGE = { [".png"] = true, [".jpg"] = true, [".tga"] = true, [".blp"] = true }
local IS_FONT = { [".ttf"] = true, [".otf"] = true }
local MAX_ID = 2 ^ 53

-- The lowercase extension (".png") of a file name, or nil; leading dots belong to the name (os.path.splitext).
local function extensionOf(name)
  return name:gsub("^%.+", ""):lower():match("%.[^.]*$")
end

-- The "/"-split parts of a path, or nil when any part could leave a root: empty after stripping spaces and dots, or
-- holding ":" or NUL (`safe_parts`).
local function safeParts(path)
  if type(path) ~= "string" then
    return nil
  end
  local parts = {}
  for part in (path:gsub("[\\]", "/") .. "/"):gmatch("([^/]*)/") do
    local unsafe = not part:find("[^ .]") or part:find(":", 1, true) or part:find("\0", 1, true)
    if unsafe then
      return nil
    end
    parts[#parts + 1] = part
  end
  return parts
end

local function slice(parts, from)
  local rest = {}
  for index = from, #parts do
    rest[#rest + 1] = parts[index]
  end
  return rest
end

local function withoutImageExtension(parts)
  local last = parts[#parts]
  local extension = extensionOf(last)
  local stripped = slice(parts, 1)
  if IS_IMAGE[extension] then
    stripped[#stripped] = last:sub(1, #last - #extension)
  end
  return stripped
end

-- The names that match want: the exact spelling first, then the others that differ only in case, in listed order.
local function listedAs(names, want)
  local folded, matches, others = want:lower(), {}, {}
  for _, name in ipairs(names) do
    if name == want then
      matches[#matches + 1] = name
    elseif name:lower() == folded then
      others[#others + 1] = name
    end
  end
  for _, name in ipairs(others) do
    matches[#matches + 1] = name
  end
  return matches
end

-- What child looks for: the part, then (last part without an image extension) the part plus each image extension.
local function wantedNames(part, isLast)
  local wanted = { part }
  if isLast and not IS_IMAGE[extensionOf(part)] then
    for _, extension in ipairs(IMAGE_EXTENSIONS) do
      wanted[#wanted + 1] = part .. extension
    end
  end
  return wanted
end

-- Every part but the last must be a directory, the last a file.
local function fitsPosition(path, isLast)
  if isLast then
    return fs.exists(path) and not fs.isdir(path)
  end
  return fs.isdir(path)
end

-- The listed name in dir that matches part (case-insensitively), or nil. Lists only a directory fs.isdir confirms.
local function child(dir, part, isLast)
  if not fs.isdir(dir) then
    return nil
  end
  local names = fs.list(dir)
  for _, want in ipairs(wantedNames(part, isLast)) do
    for _, name in ipairs(listedAs(names, want)) do
      if fitsPosition(dir .. "/" .. name, isLast) then
        return name
      end
    end
  end
  return nil
end

-- The on-disk path of parts under root, relative to root and in the listed spelling, or nil.
local function findUnder(root, parts)
  local dir, found = root, {}
  for index, part in ipairs(parts) do
    local name = child(dir, part, index == #parts)
    if not name then
      return nil
    end
    found[#found + 1] = name
    dir = dir .. "/" .. name
  end
  return #found > 0 and table.concat(found, "/") or nil
end

-- A hit under a folder of the extract (prefix "art") or under extract.dir itself (no prefix).
local function inExtract(extract, prefix, parts)
  local rel = findUnder(prefix and (extract.dir .. "/" .. prefix) or extract.dir, parts)
  if not rel then
    return nil
  end
  return { source = "extract", path = prefix and (prefix .. "/" .. rel) or rel }
end

local function byId(extract, fileID)
  local whole = type(fileID) == "number" and fileID == math.floor(fileID) and math.abs(fileID) < MAX_ID
  return whole and inExtract(extract, "art", { "by-id", string.format("%d", fileID) }) or nil
end

local function isAddonPath(parts)
  return #parts >= 3 and parts[1]:lower() == "interface" and parts[2]:lower() == "addons"
end

-- Interface/AddOns/<name>/...: looks only in that addon's root.
local function inAddon(addonRoots, parts)
  local root = addonRoots[parts[3]:lower()]
  local rel = root and findUnder(root, slice(parts, 4))
  return rel and { source = "addon", path = rel } or nil
end

-- A font hit counts only for a file type the viewer may be handed.
local function usableFont(hit)
  return hit and IS_FONT[extensionOf(hit.path:match("[^/]*$"))] and hit or nil
end

local function locatePath(addonRoots, extract, asset)
  local parts = safeParts(asset.path)
  if not parts then
    return nil
  elseif isAddonPath(parts) then
    return inAddon(addonRoots, parts)
  end
  return extract and inExtract(extract, "art", withoutImageExtension(parts)) or nil
end

local function locateFont(addonRoots, extract, asset)
  local parts = safeParts(asset.path)
  if not parts then
    return nil
  elseif isAddonPath(parts) then
    return usableFont(inAddon(addonRoots, parts))
  end
  local underFonts = extract and parts[1]:lower() == "fonts"
  return underFonts and usableFont(inExtract(extract, nil, parts)) or nil
end

local function locateFileId(_, extract, asset)
  return extract and byId(extract, asset.fileID) or nil
end

-- The sheet of the atlas row plus its crop in texture coordinates (0-1).
local function locateAtlas(_, extract, asset)
  local row = extract and type(asset.atlas) == "string" and Client.atlas(extract, asset.atlas)
  local hit = row and byId(extract, row.file)
  if not hit then
    return nil
  end
  hit.crop = { left = row.left, right = row.right, top = row.top, bottom = row.bottom }
  return hit
end

local LOCATORS = { path = locatePath, font = locateFont, fileID = locateFileId, atlas = locateAtlas }

-- { source = "addon" | "extract", path, crop? } for one asset (path relative to that addon root or to extract.dir), or
-- nil. addonRoots = { [lowercased addon folder] = absolute root }; extract is a Client.load table or nil.
function M.locate(addonRoots, extract, asset)
  local locator = type(asset) == "table" and LOCATORS[asset.kind]
  return locator and locator(addonRoots, extract, asset) or nil
end

return M

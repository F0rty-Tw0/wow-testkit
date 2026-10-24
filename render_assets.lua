-- Asset refs of a render snapshot and their registration in snapshot.assets. Ref keys: a path -> "path:" + lowercase with
-- "/"; a number -> "id:<n>"; an atlas -> "atlas:" + lowercase; a font file -> "font:" + the path as for "path:".
-- assets[ref] = { kind = "path"|"fileID"|"atlas"|"font", path?, fileID?, atlas? } where path and atlas keep the
-- addon's spelling (path with "/"). Mirrored in viewer.js.
local M = {}

local function slashed(path)
  return (path:gsub("\\", "/"))
end

function M.refPath(path)
  return "path:" .. slashed(path):lower()
end

function M.refId(n)
  return "id:" .. string.format("%.14g", n)
end

function M.refAtlas(atlas)
  return "atlas:" .. atlas:lower()
end

local function refFont(path)
  return "font:" .. slashed(path):lower()
end

local function addPath(assets, path)
  local ref = M.refPath(path)
  assets[ref] = assets[ref] or { kind = "path", path = slashed(path) }
  return ref
end

function M.addAtlas(assets, atlas)
  local ref = M.refAtlas(atlas)
  assets[ref] = assets[ref] or { kind = "atlas", atlas = atlas }
  return ref
end

function M.addFont(assets, path)
  local ref = refFont(path)
  assets[ref] = assets[ref] or { kind = "font", path = slashed(path) }
  return ref
end

-- The ref of a texture path or fileID, registering it; nil for anything else (nil, "", a table).
function M.addFile(assets, file)
  if type(file) == "number" then
    local ref = M.refId(file)
    assets[ref] = assets[ref] or { kind = "fileID", fileID = file }
    return ref
  elseif type(file) == "string" and file ~= "" then
    return addPath(assets, file)
  end
  return nil
end

return M

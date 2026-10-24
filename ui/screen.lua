-- The physical screen and the UI scale. w.screen = { width, height, useUiScale, uiScale }: physical pixels plus
-- the two CVars (useUiScale, uiScale) until Phase 7's CVar fakes exist.
local M = {}

local DEFAULT_WIDTH = 1920
local DEFAULT_HEIGHT = 1080

local function positive(value, field)
  -- NaN is the only value not equal to itself; +inf is positive, so it needs its own test.
  if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
    error("opts.screen." .. field .. " must be a positive number", 4)
  end
  return value
end

-- screen: nil | { width?, height?, useUiScale?, uiScale? }. Returns a fresh, validated table.
function M.normalize(screen)
  screen = screen or {}
  local uiScale = screen.uiScale
  if uiScale ~= nil then
    positive(uiScale, "uiScale")
  end
  return {
    width = positive(screen.width == nil and DEFAULT_WIDTH or screen.width, "width"),
    height = positive(screen.height == nil and DEFAULT_HEIGHT or screen.height, "height"),
    useUiScale = screen.useUiScale == true,
    uiScale = uiScale or 1,
  }
end

-- assumed (row LY8): UI scale is 1 while useUiScale is off, uiScale when on.
function M.uiScale(w)
  local screen = w.screen
  return screen.useUiScale and screen.uiScale or 1
end

-- source: row LY8, wiki API_GetScreenWidth: the screen is measured at UIParent scale, so UI size = physical / scale.
function M.uiSize(w)
  local scale = M.uiScale(w)
  return w.screen.width / scale, w.screen.height / scale
end

-- source: row LY8, wiki API_GetScreenWidth / API_GetScreenHeight / API_GetPhysicalScreenSize. They read w.screen,
-- not the frames, so an addon resizing UIParent does not change them.
function M.install(w)
  w:install("GetScreenWidth", function()
    return (M.uiSize(w))
  end, { gate = "api" })
  w:install("GetScreenHeight", function()
    return select(2, M.uiSize(w))
  end, { gate = "api" })
  w:install("GetPhysicalScreenSize", function()
    return w.screen.width, w.screen.height
  end, { gate = "api" })
end

return M

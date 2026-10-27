-- A font object chain read from kit state: what GetFont and GetTextColor answer, and what layout measures with,
-- without calling any method of the region (an override or hook must not run inside a layout resolve).
local M = {}

local MAX_FONT_DEPTH = 10

-- Set by ui/behaviour_button.lua: fn(w, st) -> the font object a button's state shows on its text FontString st, or
-- nil for any other region. It comes before st.fontObject, as the button applies its state font to its text.
M.ownerFont = nil

local function nextState(w, st)
  local owner = M.ownerFont and M.ownerFont(w, st)
  local fontObject = owner or st.fontObject

  return fontObject and w.ui.state[fontObject]
end

-- source(st)[key], else the first one set along the font object chain.
local function find(w, st, key, fromValues)
  for _ = 1, MAX_FONT_DEPTH do
    if not st then
      return nil
    end
    local source = fromValues and st.values or st
    if source[key] ~= nil then
      return source[key]
    end
    st = nextState(w, st)
  end
  return nil
end

-- st[field], else the first one set along the font object chain.
function M.inherited(w, st, field)
  return find(w, st, field, false)
end

-- The pack of the last SetKey call (st.values[key]), else the first one set along the font object chain.
function M.value(w, st, key)
  return find(w, st, key, true)
end

return M

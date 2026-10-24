-- A font object chain read from kit state: what GetFont and GetTextColor answer, and what layout measures with,
-- without calling any method of the region (an override or hook must not run inside a layout resolve).
local M = {}

local MAX_FONT_DEPTH = 10

-- st[field], else the first one set along the font object chain.
function M.inherited(w, st, field)
  for _ = 1, MAX_FONT_DEPTH do
    if not st then
      return nil
    end
    if st[field] ~= nil then
      return st[field]
    end
    st = st.fontObject and w.ui.state[st.fontObject]
  end
  return nil
end

return M

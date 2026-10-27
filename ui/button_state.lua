-- Shared reads of a button's state st.btn (see ui/behaviour_button.lua): the state table, and the enabled and display
-- state the state textures, the highlight and the font objects follow.
local M = {}

local NO_BUTTON = { tex = {}, fonts = {} }

-- The button state set so far; NO_BUTTON (never written) for a button nothing was set on.
function M.read(st)
  return st.btn or NO_BUTTON
end

function M.write(st)
  st.btn = st.btn or { tex = {}, fonts = {} }

  return st.btn
end

function M.isDisabled(st)
  return st.disabled == true or M.read(st).state == "DISABLED"
end

-- "disabled", "pushed" or "normal": which state texture the button shows.
function M.displayState(st)
  if M.isDisabled(st) then
    return "disabled"
  end
  if M.read(st).state == "PUSHED" then
    return "pushed"
  end

  return "normal"
end

return M

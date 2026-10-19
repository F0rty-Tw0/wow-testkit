local wrap = coroutine.wrap
coroutine = nil
wrap(function()
  while true do
  end
end)()

-- Raises the error text coroutine.wrap produced, so the run's first error shows it.
local _, err = pcall(function()
  coroutine.wrap(function()
    error("wrapped", 0)
  end)()
end)
error(err, 0)

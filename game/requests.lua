-- Server-bound calls (B13, R4 spirit): the client only asks, the server answers. Each call appends { api, args } to
-- w.mock.requests and returns the API's immediate value; the scenario plays the reply (new data plus the event).
local M = {}

M.DEFAULTS = { requests = {} }

-- Appends { api = api, args = { n = <count>, ... } } to w.mock.requests; trailing nils stay counted in args.n.
function M.record(w, api, ...)
  local requests = w.mock.requests
  requests[#requests + 1] = { api = api, args = { n = select("#", ...), ... } }
end

function M.install() end

return M

-- Poly: polyfills host library tables the way real addons do; no write may survive into the next flavor's world.
local _, ns = ...

ns.hadPoly = string.tkPoly ~= nil
string.tkPoly = true
table.wipe = table.wipe or wipe

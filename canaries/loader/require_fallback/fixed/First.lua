-- Reads ns.Later, falling back to require when Later.lua has not loaded yet.
local _, ns = ...

local Later = ns.Later or require("CanaryOrder.Later")
ns.First = { later = Later }

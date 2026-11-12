-- Synthetic fixture shaped like Ketho's CVars.lua: { CVars, PTR }, each var = { default, category, account, character, secure, help }.
local CVars = {
	var = {
		["userFontScale"] = {"1.000000", 4, false, false, false, "Scale factor for fonts"},
		["GxMonitor"] = {"0", 1, false, false, false, "Monitor index"},
	},
	command = {
		["reloadUI"] = {7, "Reloads the UI"},
	},
}

local PTR = {
	var = {
		["ptrOnly"] = {"1", 4, false, false, false, "Only on the PTR"},
	},
}

return {CVars, PTR}

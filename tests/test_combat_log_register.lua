-- Registering the combat log event: forbidden to addons on retail, ordinary elsewhere.
local A = require("assert")
local H = require("tests.helpers.combat")

local CLEU = "COMBAT_LOG_EVENT_UNFILTERED"

-- Runs an addon chunk of the addon "T" with frame in scope (no tail call: it would drop the chunk from the stack); returns the packed result ({ [1] = ok, ... }).
local function inAddon(w, frame, line)
  local chunk = assert(loadstring(line, "@addon:T/Test.lua"))
  setfenv(chunk, { frame = frame })
  return w:callAsAddon(chunk)
end

local function counter(frame)
  local seen = { n = 0 }
  frame:SetScript("OnEvent", function()
    seen.n = seen.n + 1
  end)
  return seen
end

-- source: confirmed (row C1) retail 12.0.0 fires ADDON_ACTION_FORBIDDEN when an addon registers the event; assumed the
-- call does not raise, registers nothing and returns false.
local function test_cleu_register_is_forbidden_on_retail_assumed()
  H.withScenario("retail", function(w)
    local forbidden = H.watch(w, { "ADDON_ACTION_FORBIDDEN" })
    local frame = _G.CreateFrame("Frame")
    local seen = counter(frame)
    local result = inAddon(w, frame, "local ok = frame:RegisterEvent('" .. CLEU .. "') return ok")
    A.same({ result[1], result[2] }, { true, false })
    A.same({ forbidden[1].event, forbidden[1][3], forbidden[1][4] }, { "ADDON_ACTION_FORBIDDEN", "T", "RegisterEvent()" })
    A.eq(frame:IsEventRegistered(CLEU), false)
    local entry = w.taint.log[1]
    A.same({ entry.kind, entry.addon, entry.name, entry.event }, { "blocked", "T", "RegisterEvent()", "ADDON_ACTION_FORBIDDEN" })
    w:fire(CLEU)
    A.eq(seen.n, 0)
    A.eq(#w.errors, 0)
  end)
end

-- A tail call drops the addon's chunk from the stack; the event still names the addon whose code is running.
local function test_tail_called_register_names_the_running_addon()
  H.withScenario("retail", function(w)
    local forbidden = H.watch(w, { "ADDON_ACTION_FORBIDDEN" })
    local frame = _G.CreateFrame("Frame")
    inAddon(w, frame, "return frame:RegisterEvent('" .. CLEU .. "')")
    A.same({ forbidden[1][3], forbidden[1][4] }, { "T", "RegisterEvent()" })
  end)
end

local function test_combat_log_event_and_unit_event_are_forbidden_on_retail_assumed()
  H.withScenario("retail", function(w)
    local forbidden = H.watch(w, { "ADDON_ACTION_FORBIDDEN" })
    local frame = _G.CreateFrame("Frame")
    inAddon(w, frame, "frame:RegisterEvent('COMBAT_LOG_EVENT')")
    local result = inAddon(w, frame, "local ok = frame:RegisterUnitEvent('" .. CLEU .. "', 'player') return ok")
    A.eq(result[2], false)
    A.same({ forbidden[2][4], #forbidden }, { "RegisterUnitEvent()", 2 })
    A.same({ frame:IsEventRegistered("COMBAT_LOG_EVENT"), frame:IsEventRegistered(CLEU) }, { false, false })
  end)
end

local function test_cleu_registers_normally_on_classic()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    H.withScenario(flavor, function(w)
      local forbidden = H.watch(w, { "ADDON_ACTION_FORBIDDEN" })
      local frame = _G.CreateFrame("Frame")
      local seen = counter(frame)
      inAddon(w, frame, "frame:RegisterEvent('" .. CLEU .. "')")
      w:fire(CLEU)
      A.same({ #forbidden, seen.n }, { 0, 1 })
    end)
  end
end

local function test_blizzard_code_may_register_cleu_on_retail()
  H.withScenario("retail", function(w)
    local frame = _G.CreateFrame("Frame")
    local seen = counter(frame)
    w:run("blizzard", frame.RegisterEvent, frame, CLEU)
    w:fire(CLEU)
    A.eq(seen.n, 1)
  end)
end

local function test_other_events_register_normally_on_retail()
  H.withScenario("retail", function(w)
    local frame = _G.CreateFrame("Frame")
    local result = inAddon(w, frame, "local ok = frame:RegisterEvent('PLAYER_LOGIN') return ok")
    A.same({ result[2], frame:IsEventRegistered("PLAYER_LOGIN") }, { nil, true })
  end)
end

return function()
  test_cleu_register_is_forbidden_on_retail_assumed()
  test_tail_called_register_names_the_running_addon()
  test_combat_log_event_and_unit_event_are_forbidden_on_retail_assumed()
  test_cleu_registers_normally_on_classic()
  test_blizzard_code_may_register_cleu_on_retail()
  test_other_events_register_normally_on_retail()
end

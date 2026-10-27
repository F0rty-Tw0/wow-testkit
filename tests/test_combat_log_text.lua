-- Combat log text: the viewer's one-line form of each kind of combat log entry (combat_log_text.lua).
local A = require("assert")
local H = require("tests.helpers.combat")
local Log = require("combat_log")
local Text = require("combat_log_text")

local function test_log_text_forms()
  H.withCombat("retail", function(w, _, s)
    local ann, brute = H.pair(w)
    local S = H.SPELLS
    s:advance(12.5)
    local function line(subevent, src, dst, params)
      return Text.line(w, Log.emit(w, subevent, src, dst, params))
    end
    A.same({
      line("SPELL_DAMAGE", brute, ann, { spellID = S.STRIKE, amount = 120 }),
      line("SWING_DAMAGE", brute, ann, { amount = 35 }),
      line("SPELL_HEAL", ann, ann, { spellID = S.MEND, amount = 80 }),
      line("SWING_MISSED", brute, ann, { missType = "DODGE" }),
      line("SPELL_AURA_APPLIED", ann, ann, { spellID = S.WARD, auraType = "BUFF" }),
      line("SPELL_AURA_APPLIED", brute, ann, { spellID = S.CURSE, auraType = "DEBUFF" }),
      line("SPELL_CAST_START", brute, nil, { spellID = S.BOLT }),
      line("SPELL_INTERRUPT", ann, brute, { spellID = S.STRIKE, extraSpellID = S.BOLT }),
      line("UNIT_DIED", nil, brute),
    }, {
      "[12.5] Brute: Kit Strike hits Ann for 120",
      "[12.5] Brute hits Ann for 35",
      "[12.5] Ann: Kit Mend heals Ann for 80",
      "[12.5] Brute misses Ann (DODGE)",
      "[12.5] Ann gains Kit Ward",
      "[12.5] Ann is afflicted by Kit Curse",
      "[12.5] Brute begins casting Kit Bolt",
      "[12.5] Ann: Kit Strike interrupts Brute's Kit Bolt",
      "[12.5] Brute dies",
    })
  end)
end

return function()
  test_log_text_forms()
end

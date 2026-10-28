-- Macro conditionals: SecureCmdOptionParse and MacroCond.parse/eval over the mock's combat, modifiers, group and unit
-- fixtures (rows TS16-TS17). Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")

local function parse(text)
  return { _G.SecureCmdOptionParse(text) }
end

local function test_first_matching_clause_wins_and_unconditional_clause_is_the_fallback() -- TS17
  H.withTaint("retail", function(w)
    A.same(parse("[combat] fight; calm"), { "calm" })
    H.setCombat(w, true)
    A.same(parse("[combat] fight; calm"), { "fight" })
  end)
end

local function test_comma_is_and_adjacent_brackets_are_or_assumed() -- TS17
  H.withTaint("retail", function(w)
    w:setMock({ modifiers = { shift = true } })
    A.same(parse("[mod:ctrl,mod:shift] a; [mod:shift][combat] b; c"), { "b" })
    A.same(parse("[combat][mod:shift] a; b"), { "a" }) -- only the second group holds
  end)
end

local function test_target_prefix_feeds_unit_conditions_and_the_second_result() -- TS17
  H.withTaint("retail", function(w)
    w:unit("focus", { name = "Boss", canAttack = true, health = 10, healthMax = 10 }) -- units_extra.lua:125
    A.same(parse("[@focus,harm,nodead] attack; none"), { "attack", "focus" })
    A.same(parse("[target=focus,harm] attack; none"), { "attack", "focus" })
    A.same(parse("[@mouseover,exists] x; none"), { "none" })
  end)
end

local function test_no_prefix_negates_assumed() -- TS17
  H.withTaint("retail", function(w)
    A.same(parse("[nocombat] calm; fight"), { "calm" })
    A.same(parse("[nomod] bare; held"), { "bare" })
    H.setCombat(w, true)
    w:setMock({ modifiers = { alt = true } })
    A.same(parse("[nocombat] calm; fight"), { "fight" })
    A.same(parse("[nomod] bare; held"), { "held" })
    A.same(parse("[nomod:shift] not shift; shift"), { "not shift" })
  end)
end

local function test_group_conditions_follow_the_mock()
  H.withTaint("retail", function(w)
    w:setMock({ group = "raid" })
    A.same(parse("[group:raid] r; no"), { "r" })
    A.same(parse("[group:party] p; no"), { "no" })
    A.same(parse("[group] any; no"), { "any" })
    w:setMock({ group = "party" })
    A.same(parse("[group:party] p; no"), { "p" })
    w:setMock({ group = "none" })
    A.same(parse("[group] any; no"), { "no" })
    A.same(parse("[nogroup] solo; no"), { "solo" })
  end)
end

local function test_mod_list_with_slash_is_any_of_assumed() -- TS17
  H.withTaint("retail", function(w)
    A.same(parse("[mod:shift/alt] a; b"), { "b" })
    w:setMock({ modifiers = { alt = true } })
    A.same(parse("[mod:shift/alt] a; b"), { "a" })
    A.same(parse("[mod:shift] a; b"), { "b" })
    A.same(parse("[mod] any; b"), { "any" })
    A.same(parse("[MOD:Shift/ALT] a; b"), { "a" })
  end)
end

local function test_unknown_conditional_is_false_and_counted_assumed() -- TS17
  H.withTaint("retail", function(w)
    A.same(parse("[flying] fly; walk"), { "walk" })
    A.eq(w.unscripted["macro:flying"], 1)
    A.same(parse("[noflying] walk; fly"), { "walk" })
    A.eq(w.unscripted["macro:flying"], 2) -- the no prefix reverses the false answer
  end)
end

local function test_whitespace_and_empty_brackets() -- TS17
  H.withTaint("retail", function()
    A.same(parse("[] x"), { "x" })
    A.same(parse("  [ combat , mod:shift ]  a ;  b  "), { "b" })
    A.same(parse("[combat] a"), {})
  end)
end

local function test_help_is_exists_and_not_canattack_assumed() -- TS17
  H.withTaint("retail", function(w)
    w:unit("target", { name = "Ally", canAttack = false })
    A.same(parse("[help] friend; other"), { "friend" })
    A.same(parse("[harm] foe; other"), { "other" })
    w:unit("target", { name = "Foe", canAttack = true })
    A.same(parse("[help] friend; other"), { "other" })
    w:unit("target", nil)
    A.same(parse("[help] friend; other"), { "other" })
  end)
end

local function test_btn_reads_the_clicked_button_when_one_is_given()
  H.withTaint("retail", function(w)
    local MacroCond = require("macro_cond")
    A.same({ MacroCond.eval(w, "[btn:2] right; other", { button = 2 }) }, { "right" })
    A.same({ MacroCond.eval(w, "[btn:2] right; other", { button = 1 }) }, { "other" })
    A.same({ MacroCond.eval(w, "[btn:2] right; other") }, { "other" })
  end)
end

local function test_parse_returns_clauses_of_groups_of_conditions()
  H.withTaint("retail", function()
    local MacroCond = require("macro_cond")
    local clauses = MacroCond.parse("[@focus,nocombat,mod:shift/alt][group] a; b")
    A.eq(#clauses, 2)
    A.eq(clauses[1].result, "a")
    A.eq(#clauses[1].groups, 2)
    A.eq(clauses[1].groups[1].unit, "focus")
    A.same(clauses[1].groups[1][1], { name = "combat", negate = true })
    A.same(clauses[1].groups[1][2], { name = "mod", arg = "shift/alt", negate = false })
    A.same(clauses[2], { groups = {}, result = "b" })
  end)
end

return function()
  test_first_matching_clause_wins_and_unconditional_clause_is_the_fallback()
  test_comma_is_and_adjacent_brackets_are_or_assumed()
  test_target_prefix_feeds_unit_conditions_and_the_second_result()
  test_no_prefix_negates_assumed()
  test_group_conditions_follow_the_mock()
  test_mod_list_with_slash_is_any_of_assumed()
  test_unknown_conditional_is_false_and_counted_assumed()
  test_whitespace_and_empty_brackets()
  test_help_is_exists_and_not_canattack_assumed()
  test_btn_reads_the_clicked_button_when_one_is_given()
  test_parse_returns_clauses_of_groups_of_conditions()
end

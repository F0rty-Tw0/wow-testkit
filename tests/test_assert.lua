local A = require("assert")

local function test_text_eq_reports_first_differing_line()
  local msg = A.errors(function()
    A.textEq("a\nb", "a\nc")
  end, "line 2")
  A.contains(msg, "b")
end

local function test_errors_fails_when_fn_does_not_error()
  A.errors(function()
    A.errors(function() end, "x")
  end, "expected error")
end

local function test_same_accepts_equal_nested_tables()
  A.same({ a = { 1, 2, { b = "c" } } }, { a = { 1, 2, { b = "c" } } })
end

local function test_same_rejects_false_for_absent_field()
  A.errors(function()
    A.same({ a = false }, {})
  end, "value.a")
end

return function()
  test_text_eq_reports_first_differing_line()
  test_errors_fails_when_fn_does_not_error()
  test_same_accepts_equal_nested_tables()
  test_same_rejects_false_for_absent_field()
end

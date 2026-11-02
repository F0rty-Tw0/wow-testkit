-- SimUpdate: the OnUpdate pass visits only frames that hold a handler, yet keeps the walk's rules: shown up the whole
-- parent chain, depth first in children order, roots in creation order, SetScript and HookScript both count.
local A = require("assert")
local H = require("tests.helpers.sim")

local function recorder()
  local calls = {}
  local function track(name, action)
    return function()
      calls[#calls + 1] = name
      if action then
        action()
      end
    end
  end

  return calls, track
end

local function frame(parent)
  return _G.CreateFrame("Frame", nil, parent or _G.UIParent)
end

local function test_runs_depth_first_in_creation_order()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local a, b = frame(), frame()
    local a1, a2, b1 = frame(a), frame(a), frame(b)
    local a1x = frame(a1)
    -- Set in a scrambled order: the walk's order comes from the tree, not from SetScript order.
    b1:SetScript("OnUpdate", track("b1"))
    a1x:SetScript("OnUpdate", track("a1x"))
    a2:SetScript("OnUpdate", track("a2"))
    b:SetScript("OnUpdate", track("b"))
    a:SetScript("OnUpdate", track("a"))
    a1:HookScript("OnUpdate", track("a1"))
    local _, updates = s:simStep(0.1)
    A.same(calls, { "a", "a1", "a1x", "a2", "b", "b1" })
    A.eq(updates, 6)
  end)
end

local function test_hidden_ancestor_hides_the_subtree()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local top = frame()
    local mid = frame(top)
    local leaf = frame(mid)
    leaf:SetScript("OnUpdate", track("leaf"))
    mid:Hide()
    s:simStep(0.1)
    A.same(calls, {})
    mid:Show()
    s:simStep(0.1)
    A.same(calls, { "leaf" })
    top:Hide()
    s:simStep(0.1)
    A.same(calls, { "leaf" })
  end)
end

local function test_set_script_nil_stops_the_calls_and_set_again_resumes_them()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local f = frame()
    f:SetScript("OnUpdate", track("f"))
    s:simStep(0.1)
    f:SetScript("OnUpdate", nil)
    local _, updates = s:simStep(0.1)
    A.eq(updates, 0)
    f:SetScript("OnUpdate", track("again"))
    s:simStep(0.1)
    A.same(calls, { "f", "again" })
  end)
end

local function test_a_hook_without_a_handler_runs_and_set_script_clears_it()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local f = frame()
    f:HookScript("OnUpdate", track("hook"))
    s:simStep(0.1)
    f:SetScript("OnUpdate", nil)
    s:simStep(0.1)
    A.same(calls, { "hook" })
  end)
end

local function test_a_frame_hidden_by_an_earlier_script_is_skipped()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local first, second, third = frame(), frame(), frame()
    first:SetScript(
      "OnUpdate",
      track("first", function()
        second:Hide()
      end)
    )
    second:SetScript("OnUpdate", track("second"))
    third:SetScript("OnUpdate", track("third"))
    s:simStep(0.1)
    A.same(calls, { "first", "third" })
  end)
end

local function test_a_child_moved_by_its_parents_script_runs_once_at_its_new_place()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local parent, other = frame(), frame()
    local child = frame(parent)
    parent:SetScript(
      "OnUpdate",
      track("parent", function()
        child:SetParent(other)
      end)
    )
    child:SetScript("OnUpdate", track("child"))
    other:SetScript("OnUpdate", track("other"))
    s:simStep(0.1)
    A.same(calls, { "parent", "other", "child" })
  end)
end

local function test_a_handler_set_during_the_pass_runs_from_the_next_step()
  H.withSim("retail", {}, function(_, s)
    local calls, track = recorder()
    local first, late = frame(), frame()
    first:SetScript(
      "OnUpdate",
      track("first", function()
        late:SetScript("OnUpdate", track("late"))
      end)
    )
    s:simStep(0.1)
    A.same(calls, { "first" })
    s:simStep(0.1)
    A.same(calls, { "first", "first", "late" })
  end)
end

return function()
  test_runs_depth_first_in_creation_order()
  test_hidden_ancestor_hides_the_subtree()
  test_set_script_nil_stops_the_calls_and_set_again_resumes_them()
  test_a_hook_without_a_handler_runs_and_set_script_clears_it()
  test_a_frame_hidden_by_an_earlier_script_is_skipped()
  test_a_child_moved_by_its_parents_script_runs_once_at_its_new_place()
  test_a_handler_set_during_the_pass_runs_from_the_next_step()
end

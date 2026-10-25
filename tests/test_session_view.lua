-- Session view: the inspector's widget tree (hidden and unplaced widgets too) and one widget's properties, read from
-- kit state on the SessionDemo session.
local A = require("assert")
local H = require("tests.helpers.session")
local View = require("session_view")

local function nodeNamed(tree, name)
  for _, node in ipairs(tree.nodes) do
    if node.name == name then
      return node
    end
  end
  error("no node named " .. name)
end

local function idOf(w, name)
  return nodeNamed(View.tree(w), name).id
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function test_tree_lists_hidden_frames_and_regions()
  H.withSession(nil, function(sess)
    local tree = View.tree(sess.w)
    local uiParent = nodeNamed(tree, "UIParent")
    local frame = nodeNamed(tree, "SessionDemoFrame")
    A.eq(frame.type, "Frame")
    A.eq(frame.shown, true)
    A.eq(frame.parent, uiParent.id)
    local text = nodeNamed(tree, "SessionDemoText")
    A.eq(text.id:sub(1, 1), "s")
    A.eq(text.parent, frame.id)
    local hidden = nodeNamed(tree, "SessionDemoHidden")
    A.eq(hidden.shown, false)
    A.eq(hidden.visible, false)
  end)
end

local function test_frame_props_points_size_and_rect()
  H.withSession(nil, function(sess)
    local props = View.frame(sess.w, idOf(sess.w, "SessionDemoFrame"))
    A.same(props.size, { width = 200, height = 60 })
    A.same(props.points[1], { point = "CENTER", relativeTo = idOf(sess.w, "UIParent"), relativePoint = "CENTER", x = 0, y = 0 })
    A.eq(props.strata, "MEDIUM")
    A.same(props.screenRect, { x = 860, y = 510, width = 200, height = 60 })
    A.eq(props.render.kind, "frame")
    A.truthy(contains(props.children, idOf(sess.w, "SessionDemoHidden")), "hidden child listed")
  end)
end

local function test_frame_props_scripts_and_events()
  H.withSession(nil, function(sess)
    local props = View.frame(sess.w, idOf(sess.w, "SessionDemoFrame"))
    A.same(props.scripts, { "OnEvent" })
    A.same(props.events, { "PLAYER_REGEN_DISABLED" })
  end)
end

local function test_hidden_frame_has_no_render_item()
  H.withSession(nil, function(sess)
    local props = View.frame(sess.w, idOf(sess.w, "SessionDemoHidden"))
    A.eq(props.render, nil)
    A.eq(props.visible, false)
    A.eq(props.shown, false)
  end)
end

local function test_unknown_id_is_nil()
  H.withSession(nil, function(sess)
    A.eq(View.frame(sess.w, "f99999"), nil)
    A.eq(sess:call("frame", { id = "f99999" }).ok, false)
    local reply = sess:call("frame", { id = idOf(sess.w, "SessionDemoFrame") })
    A.eq(reply.ok, true)
    A.eq(reply.props.name, "SessionDemoFrame")
    A.eq(sess:call("tree").ok, true)
  end)
end

local function test_reads_leave_unscripted_and_seq_alone()
  H.withSession(nil, function(sess)
    local before = {}
    for key, count in pairs(sess.w.unscripted) do
      before[key] = count
    end
    for _, node in ipairs(View.tree(sess.w).nodes) do
      View.frame(sess.w, node.id)
    end
    sess:call("tree")
    A.same(sess.w.unscripted, before)
    A.eq(sess.seq, 0)
  end)
end

return function()
  test_tree_lists_hidden_frames_and_regions()
  test_frame_props_points_size_and_rect()
  test_frame_props_scripts_and_events()
  test_hidden_frame_has_no_render_item()
  test_unknown_id_is_nil()
  test_reads_leave_unscripted_and_seq_alone()
end

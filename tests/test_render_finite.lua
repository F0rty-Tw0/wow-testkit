-- A number the addon stored (NaN, infinity, a nil argument) must not stop Json.encode from writing the snapshot:
-- a rect that cannot be placed is listed as unplaced, any other bad value becomes null.
local A = require("assert")
local Finite = require("render_finite")
local H = require("tests.helpers.render")
local Json = require("json")
local Render = require("render")

local NAN, INF = 0 / 0, math.huge

local function frame(name)
  local f = _G.CreateFrame("Frame", name, _G.UIParent)
  f:SetSize(10, 10)
  f:SetPoint("CENTER")
  return f
end

-- The snapshot of w and its JSON text; encoding raises when a bad number slipped through.
local function encoded(w)
  local snap = Render.snapshot(w)
  return snap, Json.encode(snap)
end

local function unplacedNames(snap)
  local names = {}
  for _, entry in ipairs(snap.unplaced) do
    names[#names + 1] = entry.name
  end
  return names
end

local function test_nan_alpha_encodes_as_null()
  H.withRender(function(w)
    frame("NanAlpha"):SetAlpha(NAN)
    local snap, text = encoded(w)
    A.eq(H.item(snap, "NanAlpha").alpha, Json.null)
    A.contains(text, '"alpha":null')
  end)
end

local function test_non_finite_size_or_offset_makes_the_region_unplaced()
  H.withRender(function(w)
    frame("InfSize"):SetSize(INF, 10)
    local offset = frame("NanOffset")
    offset:ClearAllPoints()
    offset:SetPoint("CENTER", _G.UIParent, "CENTER", NAN, 0)
    frame("Fine")
    local snap = encoded(w)
    A.eq(H.item(snap, "InfSize"), nil)
    A.eq(H.item(snap, "NanOffset"), nil)
    A.truthy(H.item(snap, "Fine"), "a finite frame is still placed")
    A.contains(unplacedNames(snap), "InfSize")
    A.contains(unplacedNames(snap), "NanOffset")
  end)
end

local function test_a_non_finite_clipping_ancestor_clips_nothing()
  H.withRender(function(w)
    local clipper = frame("NanClipper")
    clipper:SetSize(INF, 10)
    clipper:SetClipsChildren(true)
    local child = _G.CreateFrame("Frame", "ClippedKid", clipper)
    child:SetSize(10, 10)
    child:SetPoint("CENTER", _G.UIParent, "CENTER")
    local snap = encoded(w)
    A.eq(H.item(snap, "ClippedKid").clip, nil)
  end)
end

local function test_nan_texcoord_and_nil_vertex_colour_encode_as_null()
  H.withRender(function(w)
    local texture = frame("TexHost"):CreateTexture("BadTex")
    texture:SetAllPoints()
    texture:SetTexCoord(NAN, 1, 0, 1)
    texture:SetVertexColor(nil, 1, 1)
    local snap, text = encoded(w)
    local item = H.item(snap, "BadTex")
    A.same(item.texCoord, { Json.null, 0, Json.null, 1, 1, 0, 1, 1 })
    A.same(item.vertexColor, { Json.null, 1, 1, 1 })
    A.contains(text, '"texCoord":[null,0,null,1,1,0,1,1]')
  end)
end

local function test_nan_backdrop_insets_encode_as_null()
  H.withRender(function(w)
    local f = _G.CreateFrame("Frame", "BadBD", _G.UIParent, "BackdropTemplate")
    f:SetSize(10, 10)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "InterfaceButtonsWHITE8X8", insets = { left = NAN, right = 1, top = 1, bottom = 1 } })
    local snap, text = encoded(w)
    A.eq(H.piece(snap, "BadBD", "center").backdrop.insets.left, Json.null)
    A.contains(text, '"left":null')
  end)
end

local function test_negative_infinite_alpha_encodes_as_null()
  H.withRender(function(w)
    frame("NegInfAlpha"):SetAlpha(-INF)
    local snap, text = encoded(w)
    A.eq(H.item(snap, "NegInfAlpha").alpha, Json.null)
    A.contains(text, '"alpha":null')
  end)
end

-- A stored table whose numeric keys are far apart (an infinite key would loop forever, 2^22 would write 46 MB of
-- nulls) is not a list; it becomes null, as does a table that mixes names with positions.
local function test_a_sparse_or_mixed_stored_table_encodes_as_null()
  local bad = { { [INF] = 1 }, { [-INF] = 1 }, { [2 ^ 22] = 1 }, { [1.5] = 1 }, { [0] = 1 }, { 1, 2, name = "x" } }
  H.withRender(function(w)
    for i, stored in ipairs(bad) do
      local texture = frame("SparseHost" .. i):CreateTexture("SparseTex" .. i)
      texture:SetAllPoints()
      texture:SetBlendMode(stored)
    end
    local started = os.clock()
    local snap, text = encoded(w)
    for i = 1, #bad do
      A.eq(H.item(snap, "SparseTex" .. i).blendMode, Json.null, "table " .. i)
    end
    A.truthy(os.clock() - started < 5, "scrub stays fast")
    A.truthy(#text < 100000, "snapshot stays small")
  end)
end

-- A list with a few holes (an addon that stored nil in the middle) keeps its place, the holes read null.
local function test_a_stored_list_with_a_small_hole_keeps_its_length()
  H.withRender(function(w)
    local texture = frame("HoleHost"):CreateTexture("HoleTex")
    texture:SetAllPoints()
    texture:SetBlendMode({ 1, nil, 3 })
    local snap = encoded(w)
    A.same(H.item(snap, "HoleTex").blendMode, { 1, Json.null, 3 })
  end)
end

-- A table that holds itself (directly or through another) would recurse forever; the table already being copied
-- reads null where it comes back.
local function test_a_stored_table_that_contains_itself_encodes_with_null_where_it_repeats()
  local own = {}
  own.self = own
  local a, b = {}, {}
  a.b, b.a = b, a
  H.withRender(function(w)
    frame("OwnHost"):CreateTexture("OwnTex"):SetAllPoints()
    _G.OwnTex:SetBlendMode(own)
    frame("LoopHost"):CreateTexture("LoopTex"):SetAllPoints()
    _G.LoopTex:SetBlendMode(a)
    local snap = encoded(w)
    A.same(H.item(snap, "OwnTex").blendMode, { self = Json.null })
    A.same(H.item(snap, "LoopTex").blendMode, { b = { a = Json.null } })
  end)
end

-- A table stored in two places without a cycle (a diamond) is no repeat to refuse: both places get the whole copy.
local function test_a_stored_table_shared_without_a_cycle_is_copied_whole_into_both_places()
  local t = { 1, 2 }
  H.withRender(function(w)
    frame("DiamondHost"):CreateTexture("DiamondTex"):SetAllPoints()
    _G.DiamondTex:SetBlendMode({ x = t, y = t })
    local snap = encoded(w)
    A.same(H.item(snap, "DiamondTex").blendMode, { x = { 1, 2 }, y = { 1, 2 } })
  end)
end

-- How many Json.null the copy t holds.
local function countNulls(t)
  if t == Json.null then
    return 1
  end
  local count = 0
  if type(t) == "table" then
    for _, member in pairs(t) do
      count = count + countNulls(member)
    end
  end
  return count
end

-- How many tables go down t[1] before Json.null or a non-table, and what ends the chain.
local function chainDepth(t)
  local depth = 0
  while type(t) == "table" and t ~= Json.null do
    depth, t = depth + 1, t[1]
  end
  return depth, t
end

-- Children shared between levels (v = { v, v } twenty-two deep) are a handful of tables but 2^22 copies, and a chain
-- of 90000 nested tables overflows the stack; the work is bounded, tables past the limits read null, and the rest of
-- the snapshot is untouched.
local function test_a_stored_table_with_shared_children_or_deep_nesting_is_copied_within_a_bound()
  local shared, deep = { 1 }, { 1 }
  for _ = 1, 22 do
    shared = { shared, shared }
  end
  for _ = 1, 90000 do
    deep = { deep }
  end
  H.withRender(function(w)
    for i, stored in ipairs({ shared, deep }) do
      frame("BoundHost" .. i):CreateTexture("BoundTex" .. i):SetAllPoints()
      _G["BoundTex" .. i]:SetBlendMode(stored)
    end
    frame("AfterBound")
    local started = os.clock()
    local snap, text = encoded(w)
    A.truthy(os.clock() - started < 5, "scrub stays fast")
    A.truthy(#text < 2000000, "snapshot stays small: " .. #text)
    A.same(H.rect(snap, "AfterBound"), { x = 955, y = 535, width = 10, height = 10 })
    A.truthy(countNulls(H.item(snap, "BoundTex1").blendMode) > 0, "repeat copies past the budget read null")
    local depth, bottom = chainDepth(H.item(snap, "BoundTex2").blendMode)
    A.truthy(depth >= 1 and depth <= 100, "the chain is cut at the depth cap, not " .. depth)
    A.eq(bottom, Json.null)
  end)
end

-- Only repeat copies and nesting are limited: a snapshot of many different tables is copied whole.
local function test_scrub_copies_many_distinct_tables_whole()
  local list = {}
  for i = 1, 30000 do
    list[i] = { i, { i } }
  end
  local copy = Finite.scrub(list)
  A.same({ #copy, copy[30000][2][1] }, { 30000, 30000 })
end

-- The member and key rules scrub applies to every table, named by their edges: a bad number reads null at any depth in
-- a named or listed member, false and strings pass through, a list keeps 16 holes and not 17 (MAX_HOLES), a key that is
-- no positive whole number makes the table null, and an empty table (a Json.object mark) is returned as it is.
local function test_scrub_applies_the_member_and_key_rules_at_their_edges()
  local sixteen, seventeen = { 1 }, { 1 }
  sixteen[18], seventeen[19] = 18, 19
  local mark = Json.object({})
  local copy = Finite.scrub({
    list = { 1, false, "s", NAN, INF, -INF, { x = NAN, y = { INF } } },
    named = { a = NAN, b = false, c = 2 },
    sixteen = sixteen,
    seventeen = seventeen,
    zero = { [0] = 1 },
    negative = { [-1] = 1 },
    fraction = { [1.5] = 1 },
    mark = mark,
  })
  local null = Json.null
  A.same(copy.list, { 1, false, "s", null, null, null, { x = null, y = { null } } })
  A.same(copy.named, { a = null, b = false, c = 2 })
  A.same({ copy.sixteen[1], copy.sixteen[2], copy.sixteen[17], copy.sixteen[18] }, { 1, null, null, 18 })
  A.eq(copy.seventeen, null)
  A.same({ copy.zero, copy.negative, copy.fraction }, { null, null, null })
  A.eq(copy.mark, mark)
end

local function test_an_empty_assets_table_still_encodes_as_an_object()
  H.withRender(function(w)
    A.contains(select(2, encoded(w)), '"assets":{}')
  end)
end

return function()
  test_nan_alpha_encodes_as_null()
  test_non_finite_size_or_offset_makes_the_region_unplaced()
  test_a_non_finite_clipping_ancestor_clips_nothing()
  test_nan_texcoord_and_nil_vertex_colour_encode_as_null()
  test_nan_backdrop_insets_encode_as_null()
  test_negative_infinite_alpha_encodes_as_null()
  test_a_sparse_or_mixed_stored_table_encodes_as_null()
  test_a_stored_list_with_a_small_hole_keeps_its_length()
  test_a_stored_table_that_contains_itself_encodes_with_null_where_it_repeats()
  test_a_stored_table_shared_without_a_cycle_is_copied_whole_into_both_places()
  test_a_stored_table_with_shared_children_or_deep_nesting_is_copied_within_a_bound()
  test_scrub_copies_many_distinct_tables_whole()
  test_scrub_applies_the_member_and_key_rules_at_their_edges()
  test_an_empty_assets_table_still_encodes_as_an_object()
end

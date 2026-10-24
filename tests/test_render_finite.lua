-- A number the addon stored (NaN, infinity, a nil argument) must not stop Json.encode from writing the snapshot:
-- a rect that cannot be placed is listed as unplaced, any other bad value becomes null.
local A = require("assert")
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
    A.same(item.texCoord, { Json.null, 1, 0, 1 })
    A.same(item.vertexColor, { Json.null, 1, 1, 1 })
    A.contains(text, '"texCoord":[null,1,0,1]')
  end)
end

local function test_nan_backdrop_insets_encode_as_null()
  H.withRender(function(w)
    local f = _G.CreateFrame("Frame", "BadBD", _G.UIParent, "BackdropTemplate")
    f:SetSize(10, 10)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "InterfaceButtonsWHITE8X8", insets = { left = NAN, right = 1, top = 1, bottom = 1 } })
    local snap, text = encoded(w)
    A.eq(H.item(snap, "BadBD").backdrop.insets.left, Json.null)
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
  test_an_empty_assets_table_still_encodes_as_an_object()
end

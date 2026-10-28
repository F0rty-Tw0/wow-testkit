-- Mixin, CreateFromMixins and CreateAndInitFromMixin.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_mixin_copies_each_mixin_onto_the_object_and_returns_it()
  withFrameXML("retail", function(w)
    local object = { a = 0, keep = true }
    A.eq(_G.Mixin(object, { a = 1, b = 1 }, { b = 2 }), object)
    A.same(object, { a = 1, b = 2, keep = true })
    A.eq(w.unscripted.Mixin, nil)
  end)
end

local function test_create_from_mixins_returns_a_new_table_with_their_fields()
  withFrameXML("vanilla", function()
    local mixin = { a = 1 }
    local object = _G.CreateFromMixins(mixin, { b = 2 })
    A.same(object, { a = 1, b = 2 })
    A.truthy(object ~= mixin)
  end)
end

local function test_create_and_init_from_mixin_calls_init_with_the_arguments()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    withFrameXML(flavor, function()
      local mixin = {}
      function mixin:Init(x, y)
        self.sum = x + y
      end
      local object = _G.CreateAndInitFromMixin(mixin, 2, 3)
      A.eq(object.sum, 5, flavor)
      A.eq(object.Init, mixin.Init, flavor)
      A.eq(mixin.sum, nil, flavor)
    end)
  end
end

-- source: assumed (row F7); the doc gives mixins Nilable = false, the message text is the kit's argument format.
local function test_mixin_with_a_nil_mixin_raises_at_the_callers_line_assumed()
  local message
  withFrameXML("retail", function()
    local ok, err = pcall(function()
      _G.Mixin({}, { a = 1 }, nil)
    end)
    A.eq(ok, false)
    message = err
  end)
  A.contains(message, "test_mixin.lua:")
  A.contains(message, "Mixin: bad argument #3 'mixins' (table expected, got nil) on retail")
end

local function test_create_from_mixins_names_its_own_argument_assumed()
  local message
  withFrameXML("vanilla", function()
    local _, err = pcall(function()
      _G.CreateFromMixins("BoxMixin")
    end)
    message = err
  end)
  A.contains(message, "test_mixin.lua:")
  A.contains(message, "CreateFromMixins: bad argument #1 'mixins' (table expected, got string) on vanilla")
end

local function test_create_and_init_from_mixin_reports_the_create_from_mixins_argument_assumed()
  local message
  withFrameXML("retail", function()
    local _, err = pcall(function()
      _G.CreateAndInitFromMixin(nil)
    end)
    message = err
  end)
  A.contains(message, "test_mixin.lua:")
  A.contains(message, "CreateFromMixins: bad argument #1 'mixins' (table expected, got nil) on retail")
end

return function()
  test_mixin_copies_each_mixin_onto_the_object_and_returns_it()
  test_create_from_mixins_returns_a_new_table_with_their_fields()
  test_create_and_init_from_mixin_calls_init_with_the_arguments()
  test_mixin_with_a_nil_mixin_raises_at_the_callers_line_assumed()
  test_create_from_mixins_names_its_own_argument_assumed()
  test_create_and_init_from_mixin_reports_the_create_from_mixins_argument_assumed()
end

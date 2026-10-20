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

return function()
  test_mixin_copies_each_mixin_onto_the_object_and_returns_it()
  test_create_from_mixins_returns_a_new_table_with_their_fields()
  test_create_and_init_from_mixin_calls_init_with_the_arguments()
end

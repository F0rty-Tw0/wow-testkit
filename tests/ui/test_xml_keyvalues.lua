-- XML KeyValue type="global" with a dotted path (row X26); the flat form is tested in test_xml_layout.lua.
local A = require("assert")
local H = require("tests.helpers.xml")

local XML = [[
<Ui><Frame name="Kd"><KeyValues>
  <KeyValue key="flat" value="Kit" type="global"/>
  <KeyValue key="deep" value="Kit.Inner.Leaf" type="global"/>
  <KeyValue key="missing" value="Kit.Nope.Leaf" type="global"/>
  <KeyValue key="through" value="Kit.Inner.Leaf.More" type="global"/>
  <KeyValue key="nothing" value="NoSuchGlobal.Leaf" type="global"/>
</KeyValues></Frame></Ui>]]

local function test_global_keyvalue_follows_a_dotted_path_assumed()
  H.withXml({ ["Ui.xml"] = XML }, function(w, ctx)
    local kit = { Inner = { Leaf = 7 } }
    w:setGlobal("Kit", kit)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Kd.flat, _G.Kd.deep }, { kit, 7 })
    for _, key in ipairs({ "missing", "through", "nothing" }) do -- no error, no value
      A.eq(rawget(_G.Kd, key), nil, key)
    end
  end)
end

return function()
  test_global_keyvalue_follows_a_dotted_path_assumed()
end

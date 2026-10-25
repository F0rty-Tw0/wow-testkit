-- XML parser: tags, attributes, text, entities, CDATA, line numbers, malformed input. Pure: also runs on the system Lua.
local A = require("assert")
local XmlParse = require("ui.xml_parse")

local function test_parses_tags_attributes_and_children()
  local root = XmlParse.parse('<Ui><Frame name="A" hidden=\'true\'><Size x="1" y="2"/></Frame></Ui>')
  A.eq(root.tag, "ui")
  local frame = root.children[1]
  A.same({ frame.attrs.name, frame.attrs.hidden, frame.children[1].attrs.y }, { "A", "true", "2" })
end

local function test_skips_prolog_and_comments_and_decodes_entities_and_cdata()
  local root =
    XmlParse.parse('<?xml version="1.0"?><!-- c --><Ui><Script>if a &lt; b then x = "&amp;" end</Script><Script><![CDATA[a < b]]></Script></Ui>')
  A.eq(root.children[1].text, 'if a < b then x = "&" end')
  A.eq(root.children[2].text, "a < b")
end

local function test_decodes_quote_apostrophe_and_numeric_entities()
  local root = XmlParse.parse("<Ui><Script>&quot;&apos;&gt;&#65;&#x42;</Script></Ui>")
  A.eq(root.children[1].text, "\"'>AB")
end

local function test_decodes_numeric_entities_above_ascii_to_utf8()
  local root = XmlParse.parse("<Ui><Script>&#233;&#x20AC;&#x1F600;</Script></Ui>")
  A.eq(root.children[1].text, "\195\169\226\130\172\240\159\152\128")
end

local function test_records_lines()
  local root = XmlParse.parse("<Ui>\n<Frame/>\n<Script>\nx=1</Script>\n</Ui>")
  A.same({ root.line, root.children[1].line, root.children[2].line, root.children[2].textLine }, { 1, 2, 3, 3 })
end

local function test_tags_and_attribute_names_are_lowercased_assumed()
  local root = XmlParse.parse('<UI><FRAME ParentKey="K"/></UI>')
  local frame = root.children[1]
  A.same({ root.tag, frame.tag, frame.rawTag, frame.attrs.parentkey }, { "ui", "frame", "FRAME", "K" })
end

local function test_malformed_input_returns_nil_and_the_line()
  local root, message = XmlParse.parse("<Ui>\n<Frame>\n</Ui>")
  A.eq(root, nil)
  A.contains(message, "line 3")
  A.contains(message, "</Frame>")
end

local function test_unclosed_tag_unterminated_comment_and_missing_root_fail()
  local _, unclosed = XmlParse.parse("<Ui>\n<Frame>")
  A.contains(unclosed, "line 2")
  local _, comment = XmlParse.parse("<Ui>\n<!-- never closed")
  A.contains(comment, "line 2")
  local _, missing = XmlParse.parse('<?xml version="1.0"?>\n<!-- only a comment -->')
  A.contains(missing, "line 2")
end

return function()
  test_parses_tags_attributes_and_children()
  test_skips_prolog_and_comments_and_decodes_entities_and_cdata()
  test_decodes_quote_apostrophe_and_numeric_entities()
  test_decodes_numeric_entities_above_ascii_to_utf8()
  test_records_lines()
  test_tags_and_attribute_names_are_lowercased_assumed()
  test_malformed_input_returns_nil_and_the_line()
  test_unclosed_tag_unterminated_comment_and_missing_root_fail()
end

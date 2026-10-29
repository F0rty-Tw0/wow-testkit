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

local function test_lines_count_newlines_in_attributes_comments_cdata_and_text()
  local root = XmlParse.parse('<Ui\n a="x\ny">\n<!-- one\ntwo -->\n<Script><![CDATA[a\nb]]>\nc</Script>\n<?pi\n?><!DOCTYPE z>\n<Frame\n/>\n</Ui>')
  local script, frame = root.children[1], root.children[2]
  A.same({ root.line, root.textLine, script.line, script.textLine, frame.line, frame.textLine }, { 1, 3, 6, 6, 11, 12 })
  A.eq(script.text, "a\nb\nc")
end

local function test_attribute_quotes_spacing_entities_and_empty_text()
  local root = XmlParse.parse('<Ui><F a = "1"  b=\'2\' c="&lt;>" d=""\n e=\'"\'/><G/> </Ui>')
  local f = root.children[1]
  A.same({ f.attrs.a, f.attrs.b, f.attrs.c, f.attrs.d, f.attrs.e }, { "1", "2", "<>", "", '"' })
  A.same({ f.text, root.children[2].text, root.text }, { "", "", " " })
  A.eq(XmlParse.parse("<S>pre<![CDATA[<x>]]>post</S>").text, "pre<x>post")
end

local function test_bad_attributes_and_stray_markup_fail_with_the_line()
  local _, unterminated = XmlParse.parse('<Ui>\n<Frame a="1>\n</Frame></Ui>')
  A.contains(unterminated, "line 2: bad attribute in <Frame>")
  local _, unquoted = XmlParse.parse("<Ui><Frame a=1/></Ui>")
  A.contains(unquoted, "bad attribute in <Frame>")
  local _, bare = XmlParse.parse("<Ui>\n<")
  A.contains(bare, "line 2: expected a tag name")
  local _, outside = XmlParse.parse("<Ui/>\ntext")
  A.contains(outside, "line 1: text outside the root element")
end

-- How many times a private copy of the parser searches for a newline while parsing text (its `find` is a counting wrapper).
local function newlineSearches(text)
  local real, count = string.find, 0
  rawset(string, "find", function(subject, pattern, ...)
    if pattern == "\n" then
      count = count + 1
    end
    return real(subject, pattern, ...)
  end)
  local original = package.loaded["ui.xml_parse"]
  package.loaded["ui.xml_parse"] = nil
  local ok, copy = pcall(require, "ui.xml_parse")
  package.loaded["ui.xml_parse"] = original
  rawset(string, "find", real)
  assert(ok, copy)
  assert(copy.parse(text))
  return count
end

-- advance caches the next newline: thousands of tags on one line must parse to the right tree, and line numbers must
-- stay right when long lines and newlines mix (an error after a long line names that line).
local function test_long_single_line_parses_and_lines_stay_right_when_mixed_with_newlines()
  local frames = {}
  for i = 1, 3000 do
    frames[i] = '<Frame name="F' .. i .. '"><Size x="1" y="2"/></Frame>'
  end
  local row = table.concat(frames)
  local root = XmlParse.parse("<Ui>" .. row .. "</Ui>")
  A.same({ #root.children, root.children[1].attrs.name, root.children[3000].attrs.name, root.children[3000].line }, { 3000, "F1", "F3000", 1 })

  local mixed = XmlParse.parse("<Ui>" .. row .. "\n" .. row .. '\n\n<Frame name="Last"/>' .. row .. "</Ui>")
  local children = mixed.children
  A.same(
    { #children, children[3000].line, children[3001].line, children[6001].line, children[6001].attrs.name, children[6002].line },
    { 9001, 1, 2, 4, "Last", 4 }
  )

  local _, err = XmlParse.parse("<Ui>" .. row .. "\n" .. row .. "\n<Frame name=oops/></Ui>")
  A.contains(err, "line 3: bad attribute in <Frame>")

  -- Behind the timing: a line with no newline is searched once, not once per tag on it.
  A.eq(newlineSearches("<Ui>" .. row .. "</Ui>") <= 2, true, "newline searches on a single line")
  A.eq(newlineSearches("<Ui>" .. row .. "\n" .. row .. "</Ui>") <= 3, true, "newline searches on two lines")
end

return function()
  test_lines_count_newlines_in_attributes_comments_cdata_and_text()
  test_attribute_quotes_spacing_entities_and_empty_text()
  test_bad_attributes_and_stray_markup_fail_with_the_line()
  test_parses_tags_attributes_and_children()
  test_skips_prolog_and_comments_and_decodes_entities_and_cdata()
  test_decodes_quote_apostrophe_and_numeric_entities()
  test_decodes_numeric_entities_above_ascii_to_utf8()
  test_records_lines()
  test_tags_and_attribute_names_are_lowercased_assumed()
  test_malformed_input_returns_nil_and_the_line()
  test_unclosed_tag_unterminated_comment_and_missing_root_fail()
  test_long_single_line_parses_and_lines_stay_right_when_mixed_with_newlines()
end

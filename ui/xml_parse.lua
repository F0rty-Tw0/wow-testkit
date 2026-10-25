-- XML text -> node tree. A node is { tag, rawTag, attrs, children, text, line, textLine }: tag and attrs keys are
-- lowercased (the client's case rules are unsettled, so the kit is lenient); text is the element's own text and CDATA
-- with entities decoded; line is where the opening < sits and textLine where the text starts (just after the opening
-- tag). Requires only string, so it also runs on the system Lua.
local M = {}

local NAME = "[%a_:][%w_:%.%-]*"
local UTF8_BOM = "^\239\187\191"
local MAX_CODE_POINT = 0x10FFFF
local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function utf8Char(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

-- One entity reference's replacement, or nil to keep it as written.
local function entity(ref)
  local hex, dec = ref:match("^#[xX](%x+)$"), ref:match("^#(%d+)$")
  local code = hex and tonumber(hex, 16) or dec and tonumber(dec)
  if code then
    return code <= MAX_CODE_POINT and utf8Char(code) or nil
  end
  return ENTITIES[ref]
end

local function decode(text)
  return (text:gsub("&([#%w]+);", entity))
end

local function fail(line, what)
  return nil, "line " .. line .. ": " .. what
end

-- Moves the scan position to `to`, counting the lines passed.
local function advance(p, to)
  local _, newlines = p.text:sub(p.pos, to - 1):gsub("\n", "")
  p.line, p.pos = p.line + newlines, to
end

-- Skips a construct that ends at `closer` (comment, prolog, CDATA body is read by the caller).
local function skipPast(p, closer, what)
  local _, last = p.text:find(closer, p.pos, true)
  if not last then
    return fail(p.line, "unterminated " .. what)
  end
  advance(p, last + 1)
  return true
end

local function addText(p, text)
  local top = p.stack[#p.stack]
  if top then
    top.parts[#top.parts + 1] = text
    return true
  elseif text:find("%S") then
    return fail(p.line, "text outside the root element")
  end
  return true
end

local function readCdata(p)
  local top = p.stack[#p.stack]
  local body, last = p.text:match("^<!%[CDATA%[(.-)%]%]>()", p.pos)
  if not top then
    return fail(p.line, "CDATA outside the root element")
  elseif not body then
    return fail(p.line, "unterminated CDATA section")
  end
  top.parts[#top.parts + 1] = body
  advance(p, last)
  return true
end

-- Attributes of an opening tag from `pos` on: attrs, the position after the tag, whether it self-closes.
local function readAttrs(p, pos, rawTag)
  local attrs = {}
  while true do
    pos = p.text:match("^%s*()", pos)
    local closer, after = p.text:match("^(/?>)()", pos)
    if closer then
      return attrs, after, closer == "/>"
    end
    local name, quote, valueStart = p.text:match("^(" .. NAME .. ")%s*=%s*([\"'])()", pos)
    local valueEnd = name and p.text:find(quote, valueStart, true)
    if not valueEnd then
      return fail(p.line, "bad attribute in <" .. rawTag .. ">")
    end
    attrs[name:lower()] = decode(p.text:sub(valueStart, valueEnd - 1))
    pos = valueEnd + 1
  end
end

local function closeNode(p, node)
  node.text, node.parts = table.concat(node.parts), nil
  p.stack[#p.stack] = nil
  return true
end

local function readOpen(p)
  local line = p.line
  local rawTag, afterName = p.text:match("^<(" .. NAME .. ")()", p.pos)
  if not rawTag then
    return fail(line, "expected a tag name after '<'")
  end
  local attrs, after, selfClosing = readAttrs(p, afterName, rawTag)
  if not attrs then
    return nil, after
  end
  local parent = p.stack[#p.stack]
  if not parent and p.root then
    return fail(line, "more than one root element")
  end
  advance(p, after)
  local node = { tag = rawTag:lower(), rawTag = rawTag, attrs = attrs, children = {}, parts = {}, line = line, textLine = p.line }
  if parent then
    parent.children[#parent.children + 1] = node
  else
    p.root = node
  end
  p.stack[#p.stack + 1] = node
  return selfClosing and closeNode(p, node) or true
end

local function readClose(p)
  local rawTag, after = p.text:match("^</(" .. NAME .. ")%s*>()", p.pos)
  if not rawTag then
    return fail(p.line, "malformed closing tag")
  end
  local top = p.stack[#p.stack]
  if not top then
    return fail(p.line, "unexpected </" .. rawTag .. ">")
  elseif top.tag ~= rawTag:lower() then
    return fail(p.line, "expected </" .. top.rawTag .. "> but found </" .. rawTag .. ">")
  end
  advance(p, after)
  return closeNode(p, top)
end

-- Handles the markup at the scan position.
local function readMarkup(p)
  local at = p.text:sub(p.pos, p.pos + 8)
  if at:sub(1, 4) == "<!--" then
    return skipPast(p, "-->", "comment")
  elseif at == "<![CDATA[" then
    return readCdata(p)
  elseif at:sub(1, 2) == "<?" then
    return skipPast(p, "?>", "processing instruction")
  elseif at:sub(1, 2) == "<!" then
    return skipPast(p, ">", "declaration")
  elseif at:sub(1, 2) == "</" then
    return readClose(p)
  end
  return readOpen(p)
end

-- Root node, or nil and "line <n>: <what>".
function M.parse(text)
  local p = { text = text:gsub(UTF8_BOM, ""), pos = 1, line = 1, stack = {} }
  while p.pos <= #p.text do
    local lt = p.text:find("<", p.pos, true) or #p.text + 1
    local ok, message = addText(p, decode(p.text:sub(p.pos, lt - 1)))
    if not ok then
      return nil, message
    end
    advance(p, lt)
    if lt <= #p.text then
      ok, message = readMarkup(p)
      if not ok then
        return nil, message
      end
    end
  end
  local open = p.stack[#p.stack]
  if open then
    return fail(open.line, "<" .. open.rawTag .. "> is never closed")
  end
  if not p.root then
    return fail(p.line, "no root element")
  end
  return p.root
end

return M

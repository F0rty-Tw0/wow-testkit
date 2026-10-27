-- Secret values: Value.make(value, w) wraps a value in a userdata that refuses arithmetic, comparison, length, index and call for
-- addon code (an error "attempt to perform <op> on a secret <type> value"), allows concatenation of strings and numbers (the result
-- is a secret string) and a truthiness test, and passes in the engine ("blizzard" and "scenario") context. Value.reveal and
-- Value.text are for the kit's own readers (snapshots, the renderer). combat_secret.lua adds the restrictions around them.
local M = {}

local newproxy = newproxy

local TRUSTED_CONTEXTS = { blizzard = true, scenario = true }
local TEXT = { string = true, number = true }

-- Weak by key: a secret's value is reachable only through reveal.
local RECORDS = setmetatable({}, { __mode = "k" })
local PROTOTYPES = {}

function M.is(value)
  return RECORDS[value] ~= nil
end

-- The real value of a secret; any other value comes back as given. Kit-only.
function M.reveal(value)
  local record = RECORDS[value]
  if record then
    return record.value
  end
  return value
end

-- The real value as text (nil stays nil), for the readers that need a string.
function M.text(value)
  local real = M.reveal(value)
  return real ~= nil and tostring(real) or nil
end

local function trusted(record)
  return record.w ~= nil and TRUSTED_CONTEXTS[record.w:context()] == true
end

local function refuse(record, what)
  error(string.format("attempt to perform %s on a secret %s value", what, type(record.value)), 3)
end

local function binary(what, op)
  return function(a, b)
    local record = RECORDS[a] or RECORDS[b]
    if not trusted(record) then
      refuse(record, what)
    end
    return op(M.reveal(a), M.reveal(b))
  end
end

local function concat(a, b)
  local record = RECORDS[a] or RECORDS[b]
  local left, right = M.reveal(a), M.reveal(b)
  if trusted(record) then
    return left .. right
  end
  if not (TEXT[type(left)] and TEXT[type(right)]) then
    refuse(record, "concatenation")
  end
  return M.make(left .. right, record.w)
end

local function index(secret, key)
  local record = RECORDS[secret]
  if not trusted(record) then
    refuse(record, "index")
  end
  return record.value[key]
end

local function newindex(secret, key, value)
  local record = RECORDS[secret]
  if not trusted(record) then
    refuse(record, "index")
  end
  record.value[key] = value
end

local function call(secret, ...)
  local record = RECORDS[secret]
  if not trusted(record) then
    refuse(record, "call")
  end
  return record.value(...)
end

-- One function per event for every type, so Lua 5.1 finds the same __eq on both sides of a comparison.
local HANDLERS = {
  __add = binary("arithmetic", function(a, b)
    return a + b
  end),
  __sub = binary("arithmetic", function(a, b)
    return a - b
  end),
  __mul = binary("arithmetic", function(a, b)
    return a * b
  end),
  __div = binary("arithmetic", function(a, b)
    return a / b
  end),
  __mod = binary("arithmetic", function(a, b)
    return a % b
  end),
  __pow = binary("arithmetic", function(a, b)
    return a ^ b
  end),
  __unm = binary("arithmetic", function(a)
    return -a
  end),
  __lt = binary("comparison", function(a, b)
    return a < b
  end),
  __le = binary("comparison", function(a, b)
    return a <= b
  end),
  __eq = binary("comparison", function(a, b)
    return a == b
  end),
  __len = binary("length", function(a)
    return #a
  end),
  __concat = concat,
  __index = index,
  __newindex = newindex,
  __call = call,
}

-- A userdata whose metatable is made once per type name and shared by every secret of it.
local function prototype(kind)
  local proto = PROTOTYPES[kind]
  if not proto then
    proto = newproxy(true)
    local metatable = getmetatable(proto)
    for event, handler in pairs(HANDLERS) do
      metatable[event] = handler
    end
    metatable.__metatable = "secret"
    PROTOTYPES[kind] = proto
  end
  return proto
end

-- Wraps value for addon callers of world w (no world: every caller is refused). A secret stays as it is; Lua 5.1 only.
function M.make(value, w)
  if RECORDS[value] then
    return value
  end
  local secret = newproxy(prototype(type(value)))
  RECORDS[secret] = { value = value, w = w }
  return secret
end

-- True when the caller may read the value: it is not secret, or the engine is calling.
function M.accessible(value)
  local record = RECORDS[value]
  return record == nil or trusted(record)
end

return M

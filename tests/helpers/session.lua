-- Session test helpers: a Session or SessionHost on a fixture addon, always shut down so a failing test cannot leave a
-- world active, plus readers for ids and items of a session snapshot.
local Session = require("session")
local SessionHost = require("session_host")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local M = {}

local TESTS_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/helpers/[^/]*$") or "tests"

M.DEMO = TESTS_DIR .. "/fixtures/addons/SessionDemo"
M.CLICKY = TESTS_DIR .. "/fixtures/addons/Clicky"
M.WTF = TESTS_DIR .. "/fixtures/addons/WtfDemo"

-- The options a session starts with: SessionDemo on retail with a temp sessionDir, overridden by opts.
local function options(opts)
  local merged = { addonDir = M.DEMO, flavor = "retail", sessionDir = Tmp.dir("session") }
  for key, value in pairs(opts or {}) do
    merged[key] = value
  end
  return merged
end

local function guarded(subject, fn)
  local ok, err = pcall(fn, subject)
  subject:shutdown()
  if not ok then
    error(err, 0)
  end
end

-- Runs fn(sess) on Session.new(opts); the session is always shut down.
function M.withSession(opts, fn)
  guarded(Session.new(options(opts)), fn)
end

-- Runs fn(host) on SessionHost.new(opts); the host is always shut down.
function M.withHost(opts, fn)
  guarded(SessionHost.new(options(opts)), fn)
end

-- The item called name in snap, or nil.
function M.item(snap, name)
  for _, item in ipairs(snap.items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

-- The id of the item called name in sess's snapshot.
function M.id(sess, name)
  local item = M.item(sess:call("snapshot"), name)
  assert(item, "no item named " .. name)
  return item.id
end

-- A temp addon folder named name: a TOC naming Main.lua, Main.lua with body and each extra file { [relative] = text }.
function M.tempAddon(name, body, files)
  local root = Tmp.dir("sessionaddon") .. "/" .. name
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. name .. ".toc", "## Interface: 120100\nMain.lua\n")
  fs.writeFile(root .. "/Main.lua", body)
  for relative, text in pairs(files or {}) do
    fs.writeFile(root .. "/" .. relative, text)
  end
  return root
end

return M

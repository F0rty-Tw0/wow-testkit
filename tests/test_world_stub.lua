-- w:installStub, the install of every manifest and permissive-tier API name: a host-defined name is kept, a missing
-- namespace is built and removed again on destroy, a scalar on the path raises. Pins what the single namespace walk
-- (installStub no longer calls hostHas and set apart) must keep.
local A = require("assert")
local H = require("tests.helpers.world")

local withWorld, lookup = H.withWorld, H.lookup

local function test_namespaced_stub_builds_its_namespaces_and_destroy_removes_them()
  withWorld("retail", function(w)
    w:installStub("TK_Stub.Deep.Name", nil)
    A.eq(type(lookup("TK_Stub.Deep.Name")), "function")
    w:installStub("TK_Stub.Deep.Other", nil)
    A.eq(type(lookup("TK_Stub.Deep.Other")), "function")
  end)
  A.eq(rawget(_G, "TK_Stub"), nil)
end

local function test_host_defined_names_are_kept_plain_and_dotted()
  local format = string.format
  _G.TK_HostPlain = "host"
  withWorld("retail", function(w)
    w:installStub("TK_HostPlain", nil)
    w:installStub("string.format", nil)
    A.eq(_G.TK_HostPlain, "host")
    A.eq(string.format, format)
  end)
  _G.TK_HostPlain = nil
end

local function test_a_stub_replaces_an_earlier_stub_in_a_namespace_the_world_built()
  withWorld("retail", function(w)
    w:installStub("TK_Stub.Name", nil)
    local first = lookup("TK_Stub.Name")
    w:installStub("TK_Stub.Name", nil)
    A.truthy(lookup("TK_Stub.Name") ~= first, "the second stub kept the first")
  end)
end

local function test_a_new_name_in_a_host_table_is_removed_on_destroy()
  local host = {}
  _G.TK_HostNs = host
  withWorld("retail", function(w)
    w:installStub("TK_HostNs.Added", nil)
    A.eq(type(host.Added), "function")
  end)
  A.eq(rawget(host, "Added"), nil)
  _G.TK_HostNs = nil
end

local function test_a_scalar_on_the_path_raises_and_stays()
  _G.TK_Scalar = 1
  withWorld("retail", function(w)
    A.errors(function()
      w:installStub("TK_Scalar.Name", nil)
    end, "cannot install 'TK_Scalar.Name'")
    A.eq(_G.TK_Scalar, 1)
  end)
  _G.TK_Scalar = nil
end

return function()
  test_namespaced_stub_builds_its_namespaces_and_destroy_removes_them()
  test_host_defined_names_are_kept_plain_and_dotted()
  test_a_stub_replaces_an_earlier_stub_in_a_namespace_the_world_built()
  test_a_new_name_in_a_host_table_is_removed_on_destroy()
  test_a_scalar_on_the_path_raises_and_stays()
end

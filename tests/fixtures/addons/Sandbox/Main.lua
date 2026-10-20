-- Sandbox: probes which globals addon code can reach. WoW's client has no io, package, loadfile, dofile, debug or
-- require, and its os table only has the time functions.
local _, ns = ...

ns.seen = {
  gRequire = type(_G.require),
  io = type(io),
  package = type(package),
  loadfile = type(loadfile),
  dofile = type(dofile),
  debug = type(debug),
  gIo = type(_G.io),
  gG = _G._G == _G,
}
ns.osTime = type(os.time())
ns.osExecute = type(os.execute)
ns.loadstring = type(loadstring)
ns.getfenv = type(getfenv)
ns.fenvRequire = type(getfenv(0).require)
ns.loadstringRequire = type(loadstring("return require")())
ns.loadstringIo = type(loadstring("return io")())
ns.rawRequire = type(rawget(_G, "require"))
ns.pairsIo = false
for key, value in pairs(_G) do
  if key == "io" or (key == "_G" and value ~= _G) then
    ns.pairsIo = true
  end
end
_G.SandboxFoo = 1
ns.rawFoo = rawget(_G, "SandboxFoo")
ns.pairsFoo = false
for key in pairs(_G) do
  ns.pairsFoo = ns.pairsFoo or key == "SandboxFoo"
end

# Canaries

A canary proves a kit check catches a real bug. Each lives at `canaries/<layer>/<name>/` with a `canary.lua`, a
`bug/` variant that contains the bug, and a `fixed/` variant that does not.

`canary.lua` is loaded with its own directory as `...` and returns
`{ name, layer, flavors = { ... } (default { "retail" }), knownMiss = bool, check = function(variant, flavor) }`.
`check` receives `"bug"` or `"fixed"` and returns a list of finding strings; an empty list means "not flagged".

A canary passes for a flavor when `bug` has at least one finding and `fixed` has none. A `knownMiss` canary records a
bug the kit cannot catch yet: it passes while `bug` stays unflagged and fails once it is flagged, so the ceiling gets
updated. Run them with `python tools/run51.py --script canaries/run.lua [layer]`; `_synthetic/` only tests the harness.

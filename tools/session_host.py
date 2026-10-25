"""Python side of the session host: one lupa runtime holding one Lua SessionHost, and the step the Lua side leaves to it,
turning each snapshot asset's `located` (where the file is) into a `url` the viewer can load.

Every call crosses as JSON text (host:handleJson(method, json)), under one lock, and the events the Lua outbox holds are
published on the bus after each call. Nothing here decides what a request means; session_host.lua does.
"""

import json
import os
import sys
import threading
from pathlib import Path

import preview_assets as pa
import run51

KIT_ROOT = pa.KIT_ROOT
if str(KIT_ROOT) not in sys.path:
    sys.path.append(str(KIT_ROOT))

from tools.client import paths  # noqa: E402  (after KIT_ROOT is importable)

# `located` sources; anything else is not a hit.
ADDON, EXTRACT = "addon", "extract"

COMPACT = (",", ":")
START = (
    "local Json = require('json')\n"
    "local SessionHost = require('session_host')\n"
    "return function(text) return SessionHost.new(Json.decode(text)) end"
)


def _is_addon_path(asset):
    parts = pa.safe_parts(asset.get("path"))
    return bool(parts) and len(parts) >= 3 and [p.casefold() for p in parts[:2]] == ["interface", "addons"]


def _addon_root(asset, addon_roots):
    """The root folder of the addon an Interface/AddOns/<name>/... asset names, or None."""
    parts = pa.safe_parts(asset.get("path")) if _is_addon_path(asset) else None
    return addon_roots.get(parts[2].casefold()) if parts else None


def _confined(root, relative):
    """The file `relative` names under `root`, or None unless its real path stays inside root's real path."""
    try:
        path = os.path.join(root, relative)
        if not (pa._inside(os.path.realpath(root), path) and os.path.isfile(path)):
            return None
        return Path(os.path.realpath(path))
    except (OSError, ValueError, TypeError):
        return None


def _crop(extract_dir, asset):
    try:
        from tools.client import atlas

        found = atlas.crop(extract_dir, str(asset["atlas"]))
    except Exception:  # an unreadable extract or sheet is a miss, not a reason to fail the snapshot
        return None
    return Path(found) if found else None


def _located_file(asset, located, addon_roots, extract_dir):
    """(source, file) for a hit of Lua's Assets.locate that stays inside its root; (None, None) otherwise."""
    if not isinstance(located, dict) or not isinstance(located.get("path"), str):
        return None, None
    source = located.get("source")
    if source == ADDON:
        root = _addon_root(asset, addon_roots)
    elif source == EXTRACT:
        root = extract_dir
    else:
        root = None
    if root is None:
        return None, None
    if source == EXTRACT and located.get("crop") and asset.get("kind") == "atlas":
        return source, _crop(extract_dir, asset)
    return source, _confined(root, located["path"])


def _locate_miss(ref, asset, extract_dir):
    """(source, file or stand-in factory or None) for an asset Lua found no file for: what locate does after its lookups."""
    if extract_dir and not (asset.get("kind") == "path" and _is_addon_path(asset)):
        lazy = pa._lazy_extract(extract_dir, asset)
        if lazy:
            return EXTRACT, Path(lazy)
    return pa.locate(ref, asset, {}, None)


def _derive(ref, asset, located, addon_roots, extract_dir, assets_dir):
    """The source, url?, missing? and label? of one asset."""
    source, src = _located_file(asset, located, addon_roots, extract_dir)
    if src is None:
        source, src = _locate_miss(ref, asset, extract_dir)
    derived = {"source": source}
    if src is not None:
        try:
            assets_dir.mkdir(parents=True, exist_ok=True)
            derived["url"] = pa.write_asset(ref, asset, src, assets_dir)
        except Exception:  # an undecodable or unwritable file is a missing one, not a reason to fail the snapshot
            derived["source"] = "placeholder"
    if derived["source"] == "placeholder":
        derived["missing"] = True
        derived["label"] = pa.label_of(asset)
    return derived


def resolve_located(assets, addon_roots, extract_dir, assets_dir, cache=None):
    """Replaces each asset's `located` (Lua's Assets.locate) with source, url?, missing?, label?, in place; returns assets.

    A hit is served only when its real path stays inside its root (the addon folder, the extract), else it counts as
    a miss. cache (a dict) keeps the result per ref and located JSON, so a snapshot every half second writes no file twice.
    """
    assets_dir = Path(assets_dir)
    for ref, asset in assets.items():
        if not isinstance(asset, dict):
            continue
        located = asset.pop("located", None)
        key = (ref, json.dumps(located, sort_keys=True))
        if cache is None or key not in cache:
            derived = _derive(ref, asset, located, addon_roots, extract_dir, assets_dir)
            if cache is not None:
                cache[key] = derived
        else:
            derived = cache[key]
        for name in pa.DERIVED:
            asset.pop(name, None)
        asset.update(derived)
    return assets


def session_dir_for(addon_dir):
    """<testkit home>/session/<the addon folder's name, safe as a folder name>."""
    name = "".join(c if c.isalnum() or c in "_.-" else "_" for c in Path(addon_dir).name) or "addon"
    return paths.testkit_home() / "session" / name


class LuaHost:
    """One SessionHost in its own Lua runtime; every call holds one lock and publishes the events it queued on bus."""

    def __init__(self, bus, addon_dir, flavor="retail", size=(1920, 1080), extract=None, bindings=None, session_dir=None):
        self.bus = bus
        self.lock = threading.RLock()
        self.cache = {}
        self.extract_dir = extract
        session_dir = Path(session_dir) if session_dir else session_dir_for(addon_dir)
        self.assets_dir = session_dir / "preview" / "assets"
        lua = run51.new_runtime(register_eval=False, register_builtins=False)
        root = KIT_ROOT.as_posix()
        package = lua.globals().package
        package.path = root + "/?.lua;" + root + "/?/init.lua;" + package.path
        options = {
            "addonDir": Path(addon_dir).as_posix(),
            "flavor": flavor,
            "screen": {"width": size[0], "height": size[1]},
            "sessionDir": session_dir.as_posix(),
            "extract": Path(extract).as_posix() if extract else None,
            "bindingsFile": Path(bindings).as_posix() if bindings else None,
        }
        text = json.dumps({key: value for key, value in options.items() if value is not None})
        with self.lock:
            self.host = lua.execute(START)(text)
            self.addon_roots = dict(self.host.addonRoots.items())
            self._publish()

    def _publish(self):
        """Publishes the queued events; a reload among them (a reload call or a /reload) drops the asset cache."""
        for entry in json.loads(self.host.drain(self.host)):
            if entry["event"] == "reload":
                self.cache.clear()
            self.bus.publish(entry["event"], entry["data"])

    def call_json(self, method, text):
        """host:handleJson(method, text) as it replies, then the queued events published."""
        with self.lock:
            reply = self.host.handleJson(self.host, method, text)
            self._publish()
            return reply

    def call(self, method, req):
        return json.loads(self.call_json(method, json.dumps(req)))

    def snapshot_json(self):
        """The snapshot call's reply with every asset's `located` turned into `url`."""
        with self.lock:
            reply = json.loads(self.call_json("snapshot", "{}"))
            if isinstance(reply.get("assets"), dict):
                resolve_located(reply["assets"], self.addon_roots, self.extract_dir, self.assets_dir, self.cache)
            return json.dumps({"ver": reply.pop("ver"), **reply} if "ver" in reply else reply, separators=COMPACT)

    def shutdown(self):
        with self.lock:
            self.host.shutdown(self.host)

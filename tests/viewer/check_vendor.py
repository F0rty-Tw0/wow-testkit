#!/usr/bin/env python3
"""Checks the vendored three bundle and CC0 models (viewer/vendor) and the tool that wraps them.

    python -I tests/viewer/check_vendor.py

Self-tests tools/vendor/wrap_glb.py on in-memory models (wrap, --list, --clips, .gltf input), then checks the bundle
(hash, size, revision, license) and the eight model files with their CREDITS.md rows. Prints "PASS vendor: <what>" or
"FAIL vendor: <what>" per check; exit 1 on any FAIL.
"""

import base64
import hashlib
import json
import os
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WRAP = os.path.join(ROOT, "tools", "vendor", "wrap_glb.py")
VENDOR = os.path.join(ROOT, "viewer", "vendor")
MODELS = ("knight", "barbarian", "mage", "ranger", "rogue", "skeleton", "tree", "rock")
MODELS_CAP = 12582912
PREFIX = 'window.TK=window.TK||{};TK.models=TK.models||{};TK.models["%s"]="'
IMAGE = b"tiny-image-bytes"
BACKSLASH = chr(92)


def glb(doc, blob=b""):
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text
    if blob:
        blob += b"\0" * (-len(blob) % 4)
        body += struct.pack("<II", len(blob), 0x004E4942) + blob

    return struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body


def unglb(data):
    """(doc, bin) of a GLB, minimal reader."""
    assert data[:4] == b"glTF", "not a GLB"
    length, _ = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20 : 20 + length])
    rest = data[20 + length :]

    return doc, (rest[8 : 8 + struct.unpack_from("<I", rest, 0)[0]] if rest else b"")


def wrap(*args):
    return subprocess.run([sys.executable, "-I", WRAP, *args], capture_output=True, text=True)


def payload(path, name):
    with open(path, encoding="ascii") as handle:
        text = handle.read().strip()
    head = PREFIX % name
    assert text.startswith(head) and text.endswith('";'), "wrong wrapper"

    return base64.b64decode(text[len(head) : -2])


def write(path, data):
    with open(path, "wb") as handle:
        handle.write(data)


def check_wrap_roundtrip(tmp):
    doc = {
        "asset": {"version": "2.0"},
        "animations": [{"name": "Idle"}, {"name": "Death_A"}],
        "nodes": [{"name": "Body"}],
    }
    src, out = os.path.join(tmp, "in.glb"), os.path.join(tmp, "x.js")
    write(src, glb(doc))
    done = wrap(src, "x", out)
    assert done.returncode == 0, done.stderr
    assert payload(out, "x") == glb(doc), "payload differs from the input"
    lines = wrap("--list", src).stdout.split()
    assert lines == ["clip", "Idle", "clip", "Death_A", "node", "Body"], lines


def clip(name, base):
    return {
        "name": name,
        "samplers": [{"input": base, "output": base + 1}],
        "channels": [{"sampler": 0, "target": {"node": 0, "path": "rotation"}}],
    }


def clips_doc():
    views = [{"buffer": 0, "byteOffset": 16 * i, "byteLength": 16} for i in range(7)]
    accessors = [{"bufferView": i, "componentType": 5126, "count": 1, "type": "VEC4"} for i in range(7)]

    return {
        "asset": {"version": "2.0"},
        "nodes": [{"name": "Body", "mesh": 0}],
        "buffers": [{"byteLength": 112}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        "bufferViews": views,
        "accessors": accessors,
        "animations": [clip("Idle", 1), clip("Run", 3), clip("Walk", 5)],
    }


def check_wrap_clips(tmp):
    blob = b"".join(bytes([i]) * 16 for i in range(7))
    src, out, full = (os.path.join(tmp, name) for name in ("c.glb", "c.js", "full.js"))
    write(src, glb(clips_doc(), blob))
    assert wrap(src, "c", full).returncode == 0
    done = wrap(src, "c", out, "--clips", "Run,Nope")
    assert done.returncode == 0 and "skipped clip Nope" in done.stdout, done.stdout + done.stderr
    pruned, data = unglb(payload(out, "c"))
    assert [a["name"] for a in pruned["animations"]] == ["Run"], pruned["animations"]
    kept_counts = (len(pruned["accessors"]), len(data))
    assert kept_counts == (3, 48), "kept %d accessors, %d bytes" % kept_counts
    sampler = pruned["animations"][0]["samplers"][0]
    kept = [pruned["bufferViews"][pruned["accessors"][sampler[k]]["bufferView"]] for k in ("input", "output")]
    assert [data[v["byteOffset"] : v["byteOffset"] + 1] for v in kept] == [bytes([3]), bytes([4])], "clip data moved"
    assert os.path.getsize(out) < os.path.getsize(full), "pruned output is not smaller"
    write(os.path.join(tmp, "p.glb"), payload(out, "c"))
    listed = wrap("--list", os.path.join(tmp, "p.glb")).stdout.split()
    assert listed == ["clip", "Run", "node", "Body"], "--list shows more than the kept clip: %s" % listed


def gltf_doc(buffer_uri, image_uri):
    return {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": 8, "uri": buffer_uri}],
        "bufferViews": [{"buffer": 0, "byteLength": 8}],
        "images": [{"uri": image_uri}],
        "nodes": [{"name": "N"}],
    }


def check_wrap_gltf(tmp):
    write(os.path.join(tmp, "m.bin"), bytes(range(8)))
    write(os.path.join(tmp, "t.png"), IMAGE)
    src, out = os.path.join(tmp, "m.gltf"), os.path.join(tmp, "m.js")
    write(src, json.dumps(gltf_doc("m.bin", "t.png")).encode())
    done = wrap(src, "m", out)
    assert done.returncode == 0, done.stderr
    doc, data = unglb(payload(out, "m"))
    image = doc["images"][0]
    view = doc["bufferViews"][image["bufferView"]]
    assert "uri" not in image and image["mimeType"] == "image/png", image
    image_at = view["byteOffset"]
    assert data[:8] == bytes(range(8)) and data[image_at : image_at + len(IMAGE)] == IMAGE, "bytes lost"
    assert "uri" not in doc["buffers"][0], "buffer still external"


def refused(doc, sub, why):
    """Wraps a .gltf made from doc inside sub; expects a clean 'wrap_glb: ...' refusal and no output. Returns stderr."""
    src, out = os.path.join(sub, "r.gltf"), os.path.join(sub, "r.js")
    if os.path.exists(out):
        os.remove(out)
    write(src, json.dumps(doc).encode())
    done = wrap(src, "r", out)
    assert done.returncode != 0 and not os.path.exists(out), "accepted %s" % why
    assert done.stderr.startswith("wrap_glb: ") and "Traceback" not in done.stderr, "%s: %s" % (why, done.stderr)

    return done.stderr


def check_wrap_refuses(tmp):
    sub = os.path.join(tmp, "sub")
    os.makedirs(sub, exist_ok=True)
    write(os.path.join(sub, "t.png"), IMAGE)
    write(os.path.join(sub, "m.bin"), bytes(range(8)))
    write(os.path.join(tmp, "m.bin"), bytes(range(8)))
    write(os.path.join(tmp, "t.png"), IMAGE)
    data_uri = "data:application/octet-stream;base64,AAAAAAAAAAA="
    buffer_uris = ("../m.bin", "http://x/m.bin", data_uri, os.path.join(tmp, "m.bin"), BACKSLASH + "m.bin")
    image_uris = ("../t.png", "http://x/t.png", "C:t.png", os.path.join(tmp, "t.png"), BACKSLASH + "t.png", "/t.png")
    for uri in buffer_uris:
        message = refused(gltf_doc(uri, "t.png"), sub, "buffer URI %r" % uri)
        assert "refused URI" in message, "buffer URI %r refused for another reason: %s" % (uri, message)
    for uri in image_uris:
        message = refused(gltf_doc("m.bin", uri), sub, "image URI %r" % uri)
        assert "refused URI" in message, "image URI %r refused for another reason: %s" % (uri, message)


def link_dir(target, link):
    """A directory link at link to target: a symlink, else a Windows junction; False when neither can be made."""
    try:
        os.symlink(target, link, target_is_directory=True)
    except (OSError, NotImplementedError):
        if os.name != "nt":
            return False
        made = subprocess.run(["cmd", "/c", "mklink", "/J", link, target], capture_output=True, text=True)

        return made.returncode == 0

    return True


def check_wrap_symlink(tmp):
    sub, away = os.path.join(tmp, "linked"), os.path.join(tmp, "away")
    os.makedirs(sub, exist_ok=True)
    os.makedirs(away, exist_ok=True)
    write(os.path.join(sub, "t.png"), IMAGE)
    write(os.path.join(away, "m.bin"), bytes(range(8)))
    write(os.path.join(away, "t.png"), IMAGE)
    if not link_dir(away, os.path.join(sub, "jump")):
        print("SKIP vendor: no symlink or junction can be made here")

        return
    for doc in (gltf_doc("jump/m.bin", "t.png"), gltf_doc("m.bin", "jump/t.png")):
        write(os.path.join(sub, "m.bin"), bytes(range(8)))
        message = refused(doc, sub, "a link out of the folder")
        assert "refused URI" in message, "link out of the folder refused for another reason: %s" % message


def check_wrap_malformed(tmp):
    sub = os.path.join(tmp, "malformed")
    os.makedirs(sub, exist_ok=True)
    write(os.path.join(sub, "m.bin"), bytes(range(8)))
    bad_view = {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": 8, "uri": "m.bin"}],
        "bufferViews": [{"buffer": 5}],
    }
    refused([1, 2], sub, "a root that is not an object")
    refused(bad_view, sub, "a bufferView with no such buffer")


def check_bundle():
    path = os.path.join(VENDOR, "three.bundle.js")
    with open(path, "rb") as handle:
        data = handle.read()
    with open(path + ".sha256", encoding="ascii") as handle:
        want = handle.read().strip()
    assert hashlib.sha256(data).hexdigest() == want, "sha256 differs from three.bundle.js.sha256"
    assert 300000 <= len(data) <= 3000000, "size %d" % len(data)
    assert b'REVISION="170"' in data or b'REVISION = "170"' in data, "no REVISION 170"
    with open(os.path.join(VENDOR, "LICENSE-three.txt"), encoding="utf-8") as handle:
        assert "MIT License" in handle.read(), "LICENSE-three.txt is not MIT"


def credits_rows():
    with open(os.path.join(VENDOR, "models", "CREDITS.md"), encoding="utf-8") as handle:
        lines = [line for line in handle if line.startswith("|")]
        rows = [[c.strip().strip("`") for c in line.strip().strip("|").split("|")] for line in lines]

    return {row[0]: row for row in rows}


def check_models():
    rows, total = credits_rows(), 0
    for name in MODELS:
        path = os.path.join(VENDOR, "models", name + ".js")
        size = os.path.getsize(path)
        assert size <= 4 * 1024 * 1024, "%s.js is %d bytes" % (name, size)
        assert payload(path, name)[:4] == b"glTF", name + " is not a GLB"
        assert "CC0" in rows.get(name + ".js", [""] * 6)[4], name + " has no CC0 row in CREDITS.md"
        total += size
    assert total <= MODELS_CAP, "models total %d bytes, cap %d" % (total, MODELS_CAP)


def report(label, check, *args):
    try:
        check(*args)
    except (AssertionError, OSError, ValueError) as err:
        print("FAIL vendor: %s: %s" % (label, err))

        return 1
    print("PASS vendor: " + label)

    return 0


def main():
    failed = 0
    if os.path.isfile(WRAP):
        with tempfile.TemporaryDirectory() as tmp:
            failed += report("wrap_glb wraps and lists", check_wrap_roundtrip, tmp)
            failed += report("wrap_glb --clips prunes", check_wrap_clips, tmp)
            failed += report("wrap_glb embeds .gltf", check_wrap_gltf, tmp)
            failed += report("wrap_glb refuses unsafe URIs", check_wrap_refuses, tmp)
            failed += report("wrap_glb refuses links out of the folder", check_wrap_symlink, tmp)
            failed += report("wrap_glb reports malformed glTF", check_wrap_malformed, tmp)
    else:
        print("FAIL vendor: tools/vendor/wrap_glb.py missing")
        failed += 1
    failed += report("three bundle, hash and license", check_bundle)
    failed += report("eight models, CC0 rows, size cap", check_models)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

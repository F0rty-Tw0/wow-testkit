#!/usr/bin/env python3
"""Wraps a glTF model into a classic script the viewer loads without fetch (file:// pages).

    python -I tools/vendor/wrap_glb.py <in.glb|in.gltf> <name> <out.js> [--clips A,B,...]
    python -I tools/vendor/wrap_glb.py --list <in.glb|in.gltf>

The output is one line: window.TK=window.TK||{};TK.models=TK.models||{};TK.models["<name>"]="<base64 GLB>";
--clips keeps only the named animations and repacks the BIN chunk without the accessors and bufferViews nothing
references any more; names the model lacks are printed as "skipped clip <name>". A .gltf input gets its buffers and
images embedded; a URI with "..", a scheme (data: too), an absolute path, or a symlink that leaves the input's folder is
refused. --list prints "clip <name>" and "node <name>" lines. The input is untrusted data: nothing in it is executed, and
a malformed one ends as "wrap_glb: <reason>" with exit 1.
"""

import argparse
import base64
import json
import os
import re
import struct
import sys

MAX_JS_BYTES = 4 * 1024 * 1024
GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
MIMES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")
SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*:")
PREFIX = 'window.TK=window.TK||{};TK.models=TK.models||{};TK.models["%s"]="'


class WrapError(Exception):
    pass


def pad4(blob):
    """Pads a bytearray to a multiple of 4 in place."""
    blob.extend(b"\0" * (-len(blob) % 4))


def check_root(doc):
    if not isinstance(doc, dict):
        raise WrapError("glTF root is not an object")

    return doc


def read_glb(data):
    """The JSON document and BIN bytes of a GLB."""
    head = struct.unpack_from("<III", data, 0) if len(data) >= 12 else (0, 0, 0)
    if head[:2] != (GLB_MAGIC, 2) or head[2] > len(data):
        raise WrapError("not a GLB version 2")
    doc, blob, offset = None, b"", 12
    while offset + 8 <= head[2]:
        length, kind = struct.unpack_from("<II", data, offset)
        body = data[offset + 8 : offset + 8 + length]
        if len(body) != length:
            raise WrapError("GLB chunk runs past the end")
        if kind == JSON_CHUNK:
            doc = check_root(json.loads(body.decode("utf-8")))
        elif kind == BIN_CHUNK:
            blob = bytes(body)
        offset += 8 + length
    if doc is None:
        raise WrapError("GLB has no JSON chunk")

    return doc, blob


def chunk(kind, body, fill):
    body = body + fill * (-len(body) % 4)

    return struct.pack("<II", len(body), kind) + body


def write_glb(doc, blob):
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    chunks = chunk(JSON_CHUNK, text, b" ")
    if blob:
        chunks += chunk(BIN_CHUNK, blob, b"\0")

    return struct.pack("<III", GLB_MAGIC, 2, 12 + len(chunks)) + chunks


def is_unsafe_uri(uri):
    return not uri or ".." in uri or SCHEME_RE.match(uri) or uri.startswith(("/", "\\")) or os.path.isabs(uri)


def read_uri(base, uri):
    if is_unsafe_uri(uri):
        raise WrapError("refused URI %r" % uri)
    root = os.path.normcase(os.path.realpath(base))
    path = os.path.normcase(os.path.realpath(os.path.join(base, uri)))
    if not path.startswith(root + os.sep):
        raise WrapError("refused URI %r (resolves outside the model folder)" % uri)
    with open(path, "rb") as handle:
        return handle.read()


def embed_gltf(path):
    """A .gltf with its buffers and images packed into one BIN: (doc, blob)."""
    base = os.path.dirname(os.path.abspath(path))
    with open(path, encoding="utf-8") as handle:
        doc = check_root(json.load(handle))
    blob, starts = bytearray(), []
    for buffer in doc.get("buffers", []):
        pad4(blob)
        starts.append(len(blob))
        blob += read_uri(base, buffer.get("uri"))[: buffer["byteLength"]]
    views = doc.setdefault("bufferViews", [])
    for view in views:
        view["byteOffset"] = starts[view["buffer"]] + view.get("byteOffset", 0)
        view["buffer"] = 0
    for image in doc.get("images", []):
        mime = MIMES.get(os.path.splitext(image.get("uri") or "")[1].lower())
        if mime is None:
            raise WrapError("image %r is not png/jpeg" % image.get("uri"))
        data = read_uri(base, image["uri"])
        pad4(blob)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        blob += data
        image.update({"bufferView": len(views) - 1, "mimeType": mime})
        del image["uri"]
    doc["buffers"] = [{"byteLength": len(blob)}]

    return doc, bytes(blob)


def load(path):
    if path.lower().endswith(".gltf"):
        return embed_gltf(path)
    with open(path, "rb") as handle:
        return read_glb(handle.read())


def accessor_slots(doc):
    """Every (container, key) holding an accessor index."""
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for target in [prim.get("attributes", {})] + prim.get("targets", []):
                yield from ((target, key) for key in target)
            if "indices" in prim:
                yield prim, "indices"
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            yield skin, "inverseBindMatrices"
    for anim in doc.get("animations", []):
        for sampler in anim.get("samplers", []):
            yield sampler, "input"
            yield sampler, "output"


def view_slots(doc):
    """Every (container, key) holding a bufferView index."""
    for acc in doc.get("accessors", []):
        if "bufferView" in acc:
            yield acc, "bufferView"
        sparse = acc.get("sparse", {})
        for part in ("indices", "values"):
            if part in sparse:
                yield sparse[part], "bufferView"
    for image in doc.get("images", []):
        if "bufferView" in image:
            yield image, "bufferView"


def renumber(slots, used):
    remap = {old: new for new, old in enumerate(used)}
    for container, key in slots:
        container[key] = remap[container[key]]


def prune_clips(doc, blob, keep):
    """Drops the animations not in keep, then every accessor and bufferView left unused; repacks the BIN."""
    doc["animations"] = [anim for anim in doc.get("animations", []) if anim.get("name") in keep]
    used = sorted({c[k] for c, k in accessor_slots(doc)})
    accessors = doc.get("accessors", [])
    renumber(list(accessor_slots(doc)), used)
    doc["accessors"] = [accessors[i] for i in used]
    used = sorted({c[k] for c, k in view_slots(doc)})
    renumber(list(view_slots(doc)), used)
    views, packed = [], bytearray()
    for old in used:
        view = doc["bufferViews"][old]
        start = view.get("byteOffset", 0)
        body = blob[start : start + view["byteLength"]]
        if len(body) != view["byteLength"]:
            raise WrapError("bufferView %d runs past the BIN chunk" % old)
        pad4(packed)
        views.append({**view, "buffer": 0, "byteOffset": len(packed)})
        packed += body
    doc["bufferViews"] = views
    doc["buffers"] = [{"byteLength": len(packed)}]

    return doc, bytes(packed)


def listing(doc):
    clips = ["clip %s" % anim.get("name", "") for anim in doc.get("animations", [])]
    nodes = ["node %s" % node.get("name", "") for node in doc.get("nodes", [])]

    return clips + nodes


def wrap(src, name, out, clips):
    if not NAME_RE.match(name):
        raise WrapError("bad model name %r" % name)
    doc, blob = load(src)
    have = {anim.get("name") for anim in doc.get("animations", [])}
    for missing in [c for c in clips or [] if c not in have]:
        print("skipped clip %s" % missing)
    if clips is not None:
        doc, blob = prune_clips(doc, blob, set(clips))
    if clips is None and src.lower().endswith(".glb"):
        with open(src, "rb") as handle:
            glb = handle.read()
    else:
        glb = write_glb(doc, blob)
    text = PREFIX % name + base64.b64encode(glb).decode("ascii") + '";\n'
    if len(text) > MAX_JS_BYTES:
        raise WrapError("%s would be %d bytes, over the %d cap" % (out, len(text), MAX_JS_BYTES))
    with open(out, "w", encoding="ascii", newline="") as handle:
        handle.write(text)
    print("%s: %d bytes" % (out, len(text)))


def main(argv):
    parser = argparse.ArgumentParser(description="Wrap a glTF model into a classic script.")
    parser.add_argument("--list", action="store_true", help="print the clip and node names of the one input")
    parser.add_argument("--clips", help="comma-separated animation names to keep")
    parser.add_argument("paths", nargs="+", help="<in> <name> <out.js>, or <in> with --list")
    args = parser.parse_args(argv)
    try:
        if args.list and len(args.paths) == 1:
            print("\n".join(listing(load(args.paths[0])[0])))
        elif not args.list and len(args.paths) == 3:
            wrap(*args.paths, args.clips.split(",") if args.clips else None)
        else:
            parser.error("want <in> <name> <out.js>, or --list <in>")
    except (WrapError, OSError, ValueError, LookupError, TypeError, AttributeError) as err:
        print("wrap_glb: %s" % err, file=sys.stderr)

        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

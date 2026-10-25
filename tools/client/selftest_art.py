"""Tests for the art decoder, its lazy cache and the preview-side lookup."""

import io
import os
import sys
from pathlib import Path

from PIL import Image

from tools.client import art
from tools.client.extract import Ctx
from tools.client.fakes import FakeSource, make_blp

TOOLS = str(Path(__file__).resolve().parent.parent)


def encoded(fmt, color):
    out = io.BytesIO()
    Image.new("RGB", (2, 2), color).save(out, format=fmt)
    return out.getvalue()


def rgba(path):
    return Image.open(path).convert("RGBA")


def test_art_decodes_lazily_and_caches(tmp):
    src = FakeSource({"interface/buttons/red.blp": make_blp((255, 0, 0))})
    ex = tmp / "ex"
    ex.mkdir()
    p = art.art_png(ex, "interface/buttons/red", source=src)
    assert p == ex / "art/interface/buttons/red.png" and rgba(p).getpixel((0, 0)) == (255, 0, 0, 255)
    src.files.clear()
    assert art.art_png(ex, "interface/buttons/red", source=src) == p  # served from the cache


def test_art_by_id_and_missing_is_none(tmp):
    assert art.art_png(tmp, "interface/none", source=FakeSource({})) is None
    src = FakeSource({"interface/icons/a.blp": make_blp((0, 255, 0))}, ids={"interface/icons/a.blp": 136235})
    assert art.art_png(tmp, 136235, source=src) == tmp / "art/by-id/136235.png"


def test_decode_blp_tga_png_to_png(tmp):
    for data in (make_blp(), encoded("TGA", (0, 255, 0)), encoded("PNG", (0, 0, 255))):
        out = art.decode_to_png(data)
        assert out[:8] == b"\x89PNG\r\n\x1a\n"
    try:
        art.decode_to_png(b"not an image at all")
    except ValueError as err:
        assert str(err) == "unsupported image"
    else:
        raise AssertionError("expected ValueError")


def test_prewarm_decodes_only_the_common_prefixes(tmp):
    src = FakeSource({"interface/buttons/a.blp": make_blp(), "interface/icons/b.blp": make_blp()})
    ctx = Ctx("retail", "wow", "1", "1.0.0.1", ["enUS"])
    assert art.write(src, tmp / "out", ctx) == 1
    assert (tmp / "out/art/interface/buttons/a.png").is_file() and not (tmp / "out/art/interface/icons").exists()


def test_two_writers_of_one_png_each_leave_a_complete_file(tmp):
    target = tmp / "art/a.png"
    real = os.replace

    def interleaved(src, dst):  # a second preview writes the same PNG between this writer's write and its rename
        os.replace = real
        art.write_png(target, b"second")
        real(src, dst)

    os.replace = interleaved
    try:
        art.write_png(target, b"first")
    finally:
        os.replace = real
    assert target.read_bytes() == b"first" and [p.name for p in target.parent.iterdir()] == ["a.png"]


def test_lookup_extract_uses_lazy_art(tmp):
    sys.path.insert(0, TOOLS)
    import preview_assets

    ex = tmp / "ex"
    ex.mkdir()
    src = FakeSource({"interface/buttons/red.blp": make_blp((255, 0, 0))})
    real, art.lazy_source = art.lazy_source, lambda extract_dir: src
    try:
        asset = {"kind": "path", "path": "Interface/Buttons/Red"}
        hit = preview_assets.lookup_extract(str(ex), "path:interface/buttons/red", asset)
    finally:
        art.lazy_source = real
    assert hit == ex / "art/interface/buttons/red.png" and rgba(hit).getpixel((0, 0)) == (255, 0, 0, 255)


TESTS = [
    test_art_decodes_lazily_and_caches,
    test_art_by_id_and_missing_is_none,
    test_decode_blp_tga_png_to_png,
    test_prewarm_decodes_only_the_common_prefixes,
    test_two_writers_of_one_png_each_leave_a_complete_file,
    test_lookup_extract_uses_lazy_art,
]

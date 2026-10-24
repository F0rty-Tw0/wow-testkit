"""Tests for preview_chrome and the png command. Run through: python tools/preview.py --selftest

Chrome only starts in the pixel test, always headless with a private profile; it is skipped without Chrome.
"""

import contextlib
import http.client
import io
import json
import os
import socket
import sys
from pathlib import Path

from PIL import Image

import preview
import preview_chrome as pc

CANVAS = (11, 12, 16)
RED = (255, 0, 0)


class Skip(Exception):
    """Raised by a test that cannot run on this machine; the runner prints SKIP and does not count it."""


def write_snapshot(out, width=400, height=300, items=()):
    out.mkdir(parents=True, exist_ok=True)
    data = {"ver": 1, "screen": {"width": width, "height": height, "scale": 1}, "items": list(items), "assets": {}}
    (out / "snapshot.json").write_text(json.dumps(data), encoding="utf-8")


def get(server, path, host=None):
    conn = http.client.HTTPConnection(*server.server_address)
    conn.putrequest("GET", path, skip_host=host is not None)
    if host is not None:
        conn.putheader("Host", host)
    conn.endheaders()
    status = conn.getresponse().status
    conn.close()
    return status


def quiet_png(*args, **kwargs):
    """pc.png with its stderr message swallowed."""
    with contextlib.redirect_stderr(io.StringIO()):
        return pc.png(*args, **kwargs)


def run_main(argv):
    buf, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        code = preview.main(argv)
    return code, buf.getvalue(), err.getvalue()


@contextlib.contextmanager
def served(out):
    server = pc.start_server(out)
    try:
        yield server
    finally:
        pc.stop_server(server)


def test_chrome_args(tmp):
    url = "http://127.0.0.1:1/viewer/index.html?snapshot=/snapshot.json&bare=1"
    args = pc.chrome_args(url, "out.png", 1920, 1080, "prof")
    for wanted in ("--headless=new", "--screenshot=out.png", "--window-size=1920,1080", "--virtual-time-budget=5000"):
        assert wanted in args, (wanted, args)
    assert "--user-data-dir=prof" in args, args
    assert args[-1] == url, args


def test_server_serves_only_viewer_and_out_dir(tmp):
    out = tmp / "out"
    write_snapshot(out)
    (tmp / "secret.txt").write_text("secret", encoding="utf-8")
    with served(out) as server:
        assert server.server_address[0] == "127.0.0.1", server.server_address
        assert get(server, "/viewer/index.html") == 200
        assert get(server, "/snapshot.json") == 200
        for hostile in (
            "/%2e%2e/secret.txt",
            "/../secret.txt",
            "/viewer/%2e%2e/tools/preview.py",
            "/viewer/../tools/preview.py",
            "/%2e%2e/%2e%2e/etc/hosts",
            "/viewer/../../preview.py",
            "/viewer/%2e%2e/preview.py",
            "/viewer/..%2fpreview.py",
            "/..%5cpreview.py",
            "/viewer/",
            "/viewer",
            "//viewer/index.html",
            "/C:/Windows/win.ini",
        ):
            assert get(server, hostile) == 404, hostile
        assert get(server, "http://evil.example/snapshot.json") in (403, 404)


def test_server_serves_only_the_snapshot_and_assets_from_the_out_dir(tmp):
    out = tmp / "out"
    write_snapshot(out)
    (out / "assets").mkdir()
    (out / "assets" / "a.png").write_bytes(b"PNG")
    (out / ".step.log").write_text("log", encoding="utf-8")
    (out / "notes.txt").write_text("notes", encoding="utf-8")
    (out / "1-start").mkdir()
    (out / "1-start" / "snapshot.json").write_text("{}", encoding="utf-8")
    with served(out) as server:
        assert get(server, "/snapshot.json") == 200
        assert get(server, "/assets/a.png") == 200
        for other in ("/.step.log", "/notes.txt", "/1-start/snapshot.json", "/assets", "/assets/", "/assets/missing.png"):
            assert get(server, other) == 404, other


def test_server_refuses_a_foreign_host_header(tmp):
    write_snapshot(tmp)
    with served(tmp) as server:
        port = server.server_address[1]
        assert get(server, "/snapshot.json", host=f"evil.example:{port}") == 403
        assert get(server, "/snapshot.json", host=f"localhost:{port}") == 200


def test_server_does_not_follow_a_link_out_of_the_out_dir(tmp):
    outside = tmp / "outside"
    outside.mkdir()
    (outside / "secret.txt").write_text("secret", encoding="utf-8")
    out = tmp / "out"
    write_snapshot(out)
    (out / "assets").mkdir()
    try:
        (out / "assets" / "link").symlink_to(outside, target_is_directory=True)
    except OSError:
        raise Skip("no symlink privilege on this machine")
    with served(out) as server:
        assert get(server, "/assets/link/secret.txt") == 404


def test_png_defaults_size_to_the_snapshot_and_outline_adds_the_flag(tmp, monkeypatch):
    write_snapshot(tmp, 640, 480)
    seen = []
    monkeypatch(pc, "run_chrome", lambda command: seen.append(command) or "")
    pc.png(tmp, tmp / "a.png", chrome=sys.executable)
    pc.png(tmp, tmp / "b.png", size=(100, 50), chrome=sys.executable, outline=True)
    assert "--window-size=640,480" in seen[0], seen[0]
    assert "--window-size=100,50" in seen[1], seen[1]
    assert not seen[0][-1].endswith("&outline=1") and seen[1][-1].endswith("&bare=1&outline=1"), seen


def test_chrome_failure_exits_3_and_stops_the_server(tmp, monkeypatch):
    write_snapshot(tmp)
    started = []
    real_start = pc.start_server
    monkeypatch(pc, "start_server", lambda out: started.append(real_start(out)) or started[-1])
    # Python stands in for Chrome: it rejects the flags, writes no PNG and starts no browser.
    code = quiet_png(tmp, tmp / "x.png", chrome=sys.executable)
    assert code == 3, code
    assert len(started) == 1, started
    sock = socket.socket()
    try:
        assert sock.connect_ex(started[0].server_address) != 0, "server still accepts connections"
    finally:
        sock.close()


def test_missing_chrome_exits_3(tmp):
    write_snapshot(tmp)
    assert quiet_png(tmp, tmp / "x.png", chrome=str(tmp / "no-such-chrome")) == 3


def test_find_chrome_ignores_a_relative_path_hit(tmp, monkeypatch):
    monkeypatch(pc, "WINDOWS_CHROME", str(tmp / "no-such-chrome"))
    monkeypatch(pc.os, "environ", {})
    monkeypatch(pc.shutil, "which", lambda name: "." + os.sep + name + ".bat")
    assert pc.find_chrome() is None
    absolute = str(tmp / "chrome")
    monkeypatch(pc.shutil, "which", lambda name: absolute)
    assert pc.find_chrome() == absolute


def test_png_without_a_snapshot_exits_2(tmp):
    assert quiet_png(tmp, tmp / "x.png", chrome=sys.executable) == 2


def test_png_usage_errors_exit_2(tmp):
    for argv in (
        ["png"],
        ["png", "dir"],
        ["png", "dir", "a.png", "extra"],
        ["png", "dir", "a.png", "--size", "12x"],
        ["png", "dir", "a.png", "--size", "0x0"],
        ["png", "dir", "a.png", "--size"],
        ["png", "dir", "a.png", "--bogus"],
    ):
        code, _, err = run_main(argv)
        assert code == 2 and "usage" in err and "Traceback" not in err, (argv, code, err)


def test_png_matches_hand_known_pixels(tmp):
    chrome = pc.find_chrome()
    if chrome is None:
        raise Skip("Chrome not found")
    frame = {"id": "f1", "kind": "frame", "name": "Panel", "alpha": 1, "strata": "MEDIUM", "level": 1,
             "rect": {"x": 0, "y": 0, "width": 400, "height": 300}}
    swatch = {"id": "t2", "kind": "texture", "name": "Swatch", "parent": "f1", "alpha": 1, "layer": "ARTWORK",
              "sublevel": 0, "rect": {"x": 10, "y": 10, "width": 100, "height": 100}, "color": [1, 0, 0, 1]}
    write_snapshot(tmp, 400, 300, [frame, swatch])
    shot = tmp / "shot.png"
    assert pc.png(tmp, shot, chrome=chrome) == 0
    image = Image.open(shot).convert("RGB")
    assert image.size == (400, 300), image.size
    assert image.getpixel((50, 50)) == RED, image.getpixel((50, 50))
    assert image.getpixel((300, 250)) == CANVAS, image.getpixel((300, 250))


TESTS = [
    test_chrome_args,
    test_server_serves_only_viewer_and_out_dir,
    test_server_serves_only_the_snapshot_and_assets_from_the_out_dir,
    test_server_refuses_a_foreign_host_header,
    test_server_does_not_follow_a_link_out_of_the_out_dir,
    test_png_defaults_size_to_the_snapshot_and_outline_adds_the_flag,
    test_chrome_failure_exits_3_and_stops_the_server,
    test_missing_chrome_exits_3,
    test_find_chrome_ignores_a_relative_path_hit,
    test_png_without_a_snapshot_exits_2,
    test_png_usage_errors_exit_2,
    test_png_matches_hand_known_pixels,
]

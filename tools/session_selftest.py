"""Tests of the session server, each against a real server on a free loopback port. Run: python tools/session.py --selftest

This file holds the runner and the helpers; the tests live in session_selftest_guard.py (the guards, the token and the
connection cap), session_selftest_http.py (the HTTP surface) and session_selftest_live.py (input, reloads, the watcher,
assets and saved variables).
"""

import contextlib
import http.client
import json
import os
import shutil
import tempfile
import time
import traceback
from pathlib import Path

from PIL import Image

import session

ADDONS = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "addons"
DEMO, CLICKY, DEV_DEMO = ADDONS / "SessionDemo", ADDONS / "Clicky", ADDONS / "DevDemo"
COMBAT_DEMO = ADDONS / "CombatDemo"
STREAM_WAIT = 3


@contextlib.contextmanager
def testkit_home(tmp):
    """TESTKIT_HOME set to a temp folder, so a session writes nowhere else."""
    old = os.environ.get("TESTKIT_HOME")
    os.environ["TESTKIT_HOME"] = str(tmp / "home")
    try:
        yield
    finally:
        if old is None:
            os.environ.pop("TESTKIT_HOME", None)
        else:
            os.environ["TESTKIT_HOME"] = old


@contextlib.contextmanager
def running(tmp, addon=DEMO, watch=False, bindings=None, port=0):
    """A started session on `addon` (with a bindings file, if given) and a temp testkit home, always stopped."""
    with testkit_home(tmp):
        live = session.start(str(addon), port=port, watch=watch, bindings=bindings)
        try:
            yield live
        finally:
            live.stop()


def request(live, method, path, body=None, headers=None, token=True):
    """(status, content type, body bytes) of one request; a body (dict or str) is sent as JSON unless headers say otherwise.

    The session's token goes along as X-Session-Token unless token is False.
    """
    sent = {"Content-Type": "application/json"} if body is not None else {}
    if token:
        sent["X-Session-Token"] = live.token
    sent.update(headers or {})
    payload = body if isinstance(body, str) or body is None else json.dumps(body)
    conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
    try:
        conn.request(method, path, body=payload, headers=sent)
        reply = conn.getresponse()
        return reply.status, reply.getheader("Content-Type"), reply.read()
    finally:
        conn.close()


def get_json(live, path):
    status, _, body = request(live, "GET", path)
    assert status == 200, (path, status, body)
    return json.loads(body)


def post_json(live, path, body):
    status, _, reply = request(live, "POST", path, body)
    return status, json.loads(reply)


def item(snapshot, name):
    return next((i for i in snapshot["items"] if i.get("name") == name), None)


def open_stream(live):
    """The /stream response, once its headers (so its subscription) are in."""
    conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=STREAM_WAIT)
    conn.request("GET", "/stream", headers={"X-Session-Token": live.token})
    reply = conn.getresponse()
    assert reply.status == 200, reply.status
    return reply


def read_until(stream, wanted):
    """Lines read until one starts with `wanted`; returns it and the data line after it (if any)."""
    deadline = time.time() + STREAM_WAIT
    while time.time() < deadline:
        line = stream.readline().decode("utf-8").rstrip("\n")
        if line.startswith(wanted):
            return line, (stream.readline().decode("utf-8").rstrip("\n") if wanted.startswith("event:") else None)
    raise AssertionError(f"no {wanted!r} within {STREAM_WAIT} s")


def data_of(line):
    """The JSON of an SSE `data: ...` line."""
    return json.loads(line[len("data: ") :])


def temp_addon(tmp, name="T"):
    """A temp addon whose frame shows the 2x2 PNG Interface\\AddOns\\<name>\\pic; returns its folder."""
    root = tmp / name
    root.mkdir(parents=True)
    (root / f"{name}.toc").write_text("## Interface: 120100\nMain.lua\n", encoding="utf-8")
    lines = [
        'local f = CreateFrame("Frame", "TFrame", UIParent)',
        "f:SetSize(10, 10)",
        'f:SetPoint("CENTER")',
        "local t = f:CreateTexture()",
        "t:SetAllPoints()",
        f't:SetTexture("Interface\\\\AddOns\\\\{name}\\\\pic")',
    ]
    (root / "Main.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    Image.new("RGBA", (2, 2), (255, 0, 0, 255)).save(root / "pic.png")
    return root


def demo_copy(tmp):
    """A copy of SessionDemo in tmp, which a test may edit."""
    root = tmp / "SessionDemo"
    shutil.copytree(DEMO, root)
    return root


def loads(live):
    return get_json(live, "/snapshot")["session"]["loads"]


def wait_for(check, seconds=5):
    """True once check() is true, polling every 0.1 s for up to `seconds`."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if check():
            return True
        time.sleep(0.1)
    return False


def wait_for_loads(live, wanted, seconds=5):
    """True once the session has loaded `wanted` times, polling /snapshot for up to `seconds`."""
    return wait_for(lambda: loads(live) == wanted, seconds)


def run():
    import session_selftest_guard
    import session_selftest_http
    import session_selftest_live

    passed = failed = 0
    for test in session_selftest_guard.TESTS + session_selftest_http.TESTS + session_selftest_live.TESTS:
        try:
            with tempfile.TemporaryDirectory() as tmp:
                test(Path(tmp))
            print("PASS " + test.__name__)
            passed += 1
        except Exception:
            print("FAIL " + test.__name__)
            traceback.print_exc()
            failed += 1
    print(f"{passed} passed, {failed} failed")
    return 1 if failed else 0

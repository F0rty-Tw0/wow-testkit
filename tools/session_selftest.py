"""Tests of the session server, each against a real server on a free loopback port. Run: python tools/session.py --selftest"""

import contextlib
import http.client
import io
import json
import os
import shutil
import tempfile
import time
import traceback
from pathlib import Path

from PIL import Image

import session
import session_host
import session_http

ADDONS = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "addons"
DEMO, CLICKY = ADDONS / "SessionDemo", ADDONS / "Clicky"
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
def running(tmp, addon=DEMO, watch=False, bindings=None):
    """A started session on `addon` (with a bindings file, if given) and a temp testkit home, always stopped."""
    with testkit_home(tmp):
        live = session.start(str(addon), port=0, watch=watch, bindings=bindings)
        try:
            yield live
        finally:
            live.stop()


def request(live, method, path, body=None, headers=None):
    """(status, content type, body bytes) of one request; a body (dict or str) is sent as JSON unless headers say otherwise."""
    sent = {"Content-Type": "application/json"} if body is not None else {}
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
    conn.request("GET", "/stream")
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


# Tests -----------------------------------------------------------------------------------------------------------


def test_snapshot_over_http(tmp):
    with running(tmp) as live:
        snapshot = get_json(live, "/snapshot")
        assert snapshot["ver"] == 1
        assert item(snapshot, "SessionDemoFrame")
        assert snapshot["session"]["addon"] == "SessionDemo"


def test_input_fire_slash_state_round_trip(tmp):
    with running(tmp, CLICKY) as live:
        check = item(get_json(live, "/snapshot"), "ClickyCheck")
        status, reply = post_json(live, "/input", {"kind": "click", "target": check["id"]})
        assert (status, reply["ok"]) == (200, True), reply
        assert item(get_json(live, "/snapshot"), "ClickyCheck")["widget"]["checked"] is True
        for path, body in (
            ("/fire", {"event": "PLAYER_REGEN_DISABLED", "args": [1, None]}),
            ("/slash", {"text": "/nope"}),
            ("/state", {"mouseover": "target"}),
        ):
            status, reply = post_json(live, path, body)
            assert (status, reply["ok"]) == (200, True), (path, reply)


def test_point_click_over_http(tmp):
    with running(tmp, CLICKY) as live:
        status, reply = post_json(live, "/input", {"kind": "click", "target": {"x": 960, "y": 540}})
        assert (status, reply["ok"], reply["target"]["name"]) == (200, True, "ClickyCheck"), reply
        status, reply = post_json(live, "/input", {"kind": "enter", "target": {"x": 1500, "y": 900}})
        assert (status, reply) == (200, {"ok": True}), reply


def test_press_wheel_drag_over_http(tmp):
    with running(tmp, bindings=DEMO / "demo-bindings.wtf") as live:
        status, reply = post_json(live, "/input", {"kind": "press", "key": "K"})
        assert (status, reply["ok"], reply["binding"]) == (200, True, "SESSIONDEMO_TOGGLE"), reply
        assert item(get_json(live, "/snapshot"), "SessionDemoText")["text"] == "binding:down"
        status, reply = post_json(live, "/input", {"kind": "wheel", "target": {"x": 1260, "y": 540}, "delta": 1})
        assert (status, reply["target"]["name"]) == (200, "SessionDemoWheel"), reply
        assert item(get_json(live, "/snapshot"), "SessionDemoText")["text"] == "wheel:1"
        before = item(get_json(live, "/snapshot"), "SessionDemoDrag")["rect"]
        drag = {"kind": "drag", "from": {"x": 660, "y": 540}, "to": {"x": 760, "y": 540}}
        status, reply = post_json(live, "/input", drag)
        assert (status, reply["ok"], reply["target"]["name"]) == (200, True, "SessionDemoDrag"), reply
        after = item(get_json(live, "/snapshot"), "SessionDemoDrag")["rect"]
        assert (after["x"] - before["x"], after["y"] - before["y"]) == (100, 0), (before, after)


def test_foreign_host_header_is_refused(tmp):
    with running(tmp) as live:
        for host, expected in (("evil.example", 403), (f"127.0.0.1:{live.port}", 200), (f"localhost:{live.port}", 200)):
            conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
            conn.putrequest("GET", "/snapshot", skip_host=True)
            conn.putheader("Host", host)
            conn.endheaders()
            status = conn.getresponse().status
            conn.close()
            assert status == expected, (host, status)


def test_cross_origin_and_wrong_content_type_are_refused(tmp):
    body = {"event": "PLAYER_REGEN_DISABLED"}
    with running(tmp) as live:
        assert request(live, "POST", "/fire", body, {"Origin": "http://evil.example"})[0] == 403
        assert request(live, "POST", "/fire", body, {"Content-Type": "text/plain"})[0] == 415
        assert request(live, "POST", "/fire", body, {"Origin": f"http://127.0.0.1:{live.port}"})[0] == 200
        assert request(live, "POST", "/fire", body)[0] == 200


def test_non_loopback_bind_is_refused(tmp):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        assert session.main(["--bind", "0.0.0.0", str(DEMO)]) == 2
    assert "127.0.0.1" in err.getvalue(), err.getvalue()
    shown = []
    with contextlib.redirect_stdout(out), testkit_home(tmp):
        assert session.main(["--bind", "127.0.0.1", str(DEMO)], wait=shown.append) == 0
    assert shown and out.getvalue().startswith("session: http://127.0.0.1:"), out.getvalue()


def test_static_serving_is_confined(tmp):
    with running(tmp) as live:
        assert request(live, "GET", "/viewer/index.html")[0] == 200
        for path in ("/viewer/../tools/session.py", "/%2e%2e/session.lua", "/session.lua", "/assets/../../x"):
            assert request(live, "GET", path)[0] == 404, path


def test_root_opens_the_live_viewer_fitted(tmp):
    with running(tmp) as live:
        conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
        try:
            conn.request("GET", "/")
            reply = conn.getresponse()
            assert (reply.status, reply.getheader("Location")) == (302, "/viewer/index.html?live=1&zoom=fit"), reply.status
        finally:
            conn.close()


def test_stream_announces_changes(tmp):
    old = session_http.KEEPALIVE_SECONDS
    session_http.KEEPALIVE_SECONDS = 0.2
    try:
        with running(tmp) as live:
            stream = open_stream(live)
            read_until(stream, ": keepalive")
            assert request(live, "POST", "/fire", {"event": "PLAYER_REGEN_DISABLED"})[0] == 200
            _, data = read_until(stream, "event: snapshot")
            assert json.loads(data[len("data: ") :])["seq"] > 0, data
    finally:
        session_http.KEEPALIVE_SECONDS = old


def test_bad_requests(tmp):
    with running(tmp) as live:
        status, _, body = request(live, "POST", "/fire", "{")
        assert status == 400 and json.loads(body)["ok"] is False, (status, body)
        assert request(live, "GET", "/nope")[0] == 404
        assert request(live, "DELETE", "/snapshot")[0] == 405


def test_reload_keeps_the_server_up(tmp):
    with running(tmp) as live:
        status, reply = post_json(live, "/reload", {})
        assert (status, reply["ok"]) == (200, True), reply
        snapshot = get_json(live, "/snapshot")
        assert item(snapshot, "SessionDemoFrame")
        assert snapshot["session"]["loads"] == 2


def test_reload_flavor_and_size_over_http(tmp):
    with running(tmp) as live:
        status, reply = post_json(live, "/reload", {"flavor": "vanilla", "size": "1440p"})
        assert (status, reply["ok"], reply["flavor"], reply["screen"]) == (200, True, "vanilla", {"width": 2560, "height": 1440}), reply
        before = get_json(live, "/snapshot")
        assert before["session"]["flavor"] == "vanilla" and before["screen"]["width"] == 2560, before["session"]
        status, reply = post_json(live, "/reload", {"flavor": "x"})
        assert (status, reply["ok"]) == (400, False) and "flavor" in reply["error"], (status, reply)
        after = get_json(live, "/snapshot")
        assert after["session"] == before["session"] and after["screen"] == before["screen"], after["session"]
        assert post_json(live, "/slash", {"text": "/sdemo alive"}) == (200, {"ok": True, "handled": True})


def test_assets_resolve_and_are_served(tmp):
    with running(tmp, temp_addon(tmp)) as live:
        asset = get_json(live, "/snapshot")["assets"]["path:interface/addons/t/pic"]
        assert asset["source"] == "addon" and asset["url"].startswith("assets/"), asset
        status, content_type, _ = request(live, "GET", "/" + asset["url"])
        assert (status, content_type) == (200, "image/png")


def test_call_relays_handle_json(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        status, reply = post_json(live, "/call/slash", {"text": "/sdemo hi"})
        assert (status, reply["ok"]) == (200, True), reply
        read_until(stream, "event: snapshot")
        assert post_json(live, "/call/nope", {}) == (200, {"ok": False, "error": "unknown method 'nope'"})
        assert request(live, "POST", "/call/Bad-Name", {})[0] == 404
        status, reply = post_json(live, "/call/fire", {"event": "PLAYER_REGEN_DISABLED", "args": [None]})
        assert (status, reply["ok"]) == (200, True), reply
        assert post_json(live, "/call/fire", "{")[1]["error"].startswith("malformed request: json:")
    with running(tmp, temp_addon(tmp / "other")) as live:
        status, snapshot = post_json(live, "/call/snapshot", {})
        asset = snapshot["assets"]["path:interface/addons/t/pic"]
        assert status == 200 and asset["source"] == "addon" and "url" in asset, asset


def test_located_outside_its_root_is_not_served(tmp):
    (tmp / "T").mkdir()
    (tmp / "escape.png").write_bytes(b"not an image")
    ref = "path:interface/addons/t/x"
    assets = {ref: {"kind": "path", "path": "Interface/AddOns/T/x", "located": {"source": "addon", "path": "../escape.png"}}}
    resolved = session_host.resolve_located(assets, {"t": str(tmp / "T")}, None, tmp / "assets")
    assert resolved[ref]["source"] == "placeholder" and "url" not in resolved[ref], resolved
    assert not (tmp / "assets").exists()


def test_tree_and_frame_endpoints(tmp):
    with running(tmp) as live:
        tree = get_json(live, "/tree")
        node = next((n for n in tree["nodes"] if n.get("name") == "SessionDemoFrame"), None)
        assert tree["ok"] is True and node, tree
        reply = get_json(live, "/frame?id=" + node["id"])
        assert (reply["ok"], reply["props"]["size"]["width"]) == (True, 200), reply
        status, _, body = request(live, "GET", "/frame?id=zzz")
        assert status == 404 and json.loads(body)["ok"] is False, (status, body)


def test_console_events_stream(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        status, reply = post_json(live, "/slash", {"text": "/sdemo hi"})
        assert (status, reply) == (200, {"ok": True, "handled": True}), reply
        _, data = read_until(stream, "event: console")
        line = json.loads(data[len("data: ") :])
        assert (line["kind"], line["text"]) == ("print", "slash hi"), line


def test_state_and_events_endpoints(tmp):
    with running(tmp) as live:
        status, reply = post_json(live, "/state", {"modifiers": {"shift": True}})
        assert (status, reply["ok"]) == (200, True), reply
        state = get_json(live, "/state")
        assert state["state"]["modifiers"] == {"shift": True, "ctrl": False, "alt": False}, state
        names = [event["name"] for event in get_json(live, "/events")["events"]]
        assert "PLAYER_REGEN_DISABLED" in names, len(names)
        status, reply = post_json(live, "/state", {"modifiers": {"bogus": True}})
        assert status == 400 and "bogus" in reply["error"], (status, reply)


def test_slash_reload_serves_changed_assets(tmp):
    root = temp_addon(tmp)
    with running(tmp, root) as live:
        url = get_json(live, "/snapshot")["assets"]["path:interface/addons/t/pic"]["url"]
        Image.new("RGBA", (2, 2), (0, 0, 255, 255)).save(root / "pic.png")
        assert post_json(live, "/slash", {"text": "/reload"}) == (200, {"ok": True, "handled": True})
        assert get_json(live, "/snapshot")["session"]["loads"] == 2
        _, _, body = request(live, "GET", "/" + url)
        assert Image.open(io.BytesIO(body)).getpixel((0, 0)) == (0, 0, 255, 255)


def demo_copy(tmp):
    """A copy of SessionDemo in tmp, which a test may edit."""
    root = tmp / "SessionDemo"
    shutil.copytree(DEMO, root)
    return root


def loads(live):
    return get_json(live, "/snapshot")["session"]["loads"]


def wait_for_loads(live, wanted, seconds=5):
    """True once the session has loaded `wanted` times, polling /snapshot for up to `seconds`."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if loads(live) == wanted:
            return True
        time.sleep(0.1)
    return False


def test_file_save_reloads_and_keeps_saved_variables(tmp):
    root = demo_copy(tmp)
    with running(tmp, root, watch=True) as live:
        stream = open_stream(live)
        main = root / "Main.lua"
        main.write_text(main.read_text(encoding="utf-8").replace('"idle"', '"edited"'), encoding="utf-8")
        assert wait_for_loads(live, 2), "no reload after a save"
        assert item(get_json(live, "/snapshot"), "SessionDemoText")["text"] == "edited"
        assert post_json(live, "/slash", {"text": "/dump SessionDemoDB.runs"})[1]["ok"] is True
        deadline = time.time() + STREAM_WAIT
        while True:
            _, data = read_until(stream, "event: console")
            if json.loads(data[len("data: ") :])["text"] == "2":
                break
            assert time.time() < deadline, "no console line 2"


def test_unwatched_file_changes_do_not_reload(tmp):
    root = demo_copy(tmp)
    with running(tmp, root, watch=True) as live:
        (root / "notes.txt").write_text("x", encoding="utf-8")
        time.sleep(1.5)
        assert loads(live) == 1


def test_several_quick_saves_reload_once(tmp):
    root = demo_copy(tmp)
    with running(tmp, root, watch=True) as live:
        main = root / "Main.lua"
        for i in range(3):
            main.write_text(main.read_text(encoding="utf-8") + f"-- save {i}\n", encoding="utf-8")
            time.sleep(0.05)
        assert wait_for_loads(live, 2), "no reload after the saves"
        time.sleep(1.5)
        assert loads(live) == 2


def test_reload_event_is_streamed(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        assert post_json(live, "/reload", {})[1]["ok"] is True
        _, data = read_until(stream, "event: reload")
        assert json.loads(data[len("data: ") :]) == {"loads": 2}, data


def test_shutdown_writes_the_file(tmp):
    with testkit_home(tmp):
        live = session.start(str(DEMO), port=0)
        live.stop()
        saved = session_host.session_dir_for(DEMO) / "saved.lua"
        assert saved.is_file() and "runs = 1" in saved.read_text(encoding="utf-8"), saved


TESTS = [
    test_snapshot_over_http,
    test_input_fire_slash_state_round_trip,
    test_point_click_over_http,
    test_press_wheel_drag_over_http,
    test_foreign_host_header_is_refused,
    test_cross_origin_and_wrong_content_type_are_refused,
    test_non_loopback_bind_is_refused,
    test_static_serving_is_confined,
    test_root_opens_the_live_viewer_fitted,
    test_stream_announces_changes,
    test_bad_requests,
    test_reload_keeps_the_server_up,
    test_reload_flavor_and_size_over_http,
    test_assets_resolve_and_are_served,
    test_call_relays_handle_json,
    test_located_outside_its_root_is_not_served,
    test_tree_and_frame_endpoints,
    test_console_events_stream,
    test_state_and_events_endpoints,
    test_slash_reload_serves_changed_assets,
    test_file_save_reloads_and_keeps_saved_variables,
    test_unwatched_file_changes_do_not_reload,
    test_several_quick_saves_reload_once,
    test_reload_event_is_streamed,
    test_shutdown_writes_the_file,
]


def run():
    passed = failed = 0
    for test in TESTS:
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

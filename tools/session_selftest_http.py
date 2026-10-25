"""The session server's HTTP surface and its guards: routes, the Host/Origin/content-type checks, the session token,
static files, the stream and the /run sandbox. Run through: python tools/session.py --selftest"""

import contextlib
import http.client
import io
import json

import run51
import session
import session_host
import session_http
from session_selftest import (
    DEMO,
    DEV_DEMO,
    data_of,
    get_json,
    item,
    open_stream,
    post_json,
    read_until,
    request,
    running,
    testkit_home,
)


def test_snapshot_over_http(tmp):
    with running(tmp) as live:
        snapshot = get_json(live, "/snapshot")
        assert snapshot["ver"] == 1
        assert item(snapshot, "SessionDemoFrame")
        assert snapshot["session"]["addon"] == "SessionDemo"


def test_foreign_host_header_is_refused(tmp):
    with running(tmp) as live:
        for host, expected in (("evil.example", 403), (f"127.0.0.1:{live.port}", 200), (f"localhost:{live.port}", 200)):
            conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
            conn.putrequest("GET", "/snapshot", skip_host=True)
            conn.putheader("Host", host)
            conn.putheader("X-Session-Token", live.token)
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


def test_data_routes_need_the_token(tmp):
    with running(tmp) as live:
        for method, path, body in (
            ("GET", "/snapshot", None),
            ("GET", "/stream", None),
            ("GET", "/assets/x.png", None),
            ("POST", "/call/fire", {"event": "PLAYER_REGEN_DISABLED"}),
            ("POST", "/slash", {"text": "/sdemo hi"}),
            ("GET", "/", None),
        ):
            assert request(live, method, path, body, token=False)[0] == 401, path
            assert request(live, method, path, body, {"X-Session-Token": live.token + "x"}, token=False)[0] == 401, path
        assert request(live, "GET", "/viewer/index.html", token=False)[0] == 200


def test_token_url_sets_the_cookie_and_the_cookie_works(tmp):
    with running(tmp) as live:
        assert live.url == f"http://127.0.0.1:{live.port}/?token={live.token}"
        conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
        try:
            conn.request("GET", "/?token=" + live.token)
            reply = conn.getresponse()
            location, cookie = reply.getheader("Location"), reply.getheader("Set-Cookie")
        finally:
            conn.close()
        assert (reply.status, location) == (302, "/viewer/index.html?live=1&zoom=fit"), (reply.status, location)
        name = f"tk_session_{live.port}"
        assert cookie == f"{name}={live.token}; HttpOnly; SameSite=Strict; Path=/", cookie
        sent = {"Cookie": f"{name}={live.token}"}
        assert request(live, "GET", "/snapshot", headers=sent, token=False)[0] == 200
        assert request(live, "POST", "/slash", {"text": "/sdemo hi"}, sent, token=False)[0] == 200
        assert request(live, "GET", "/", headers=sent, token=False)[0] == 302
        other = {"Cookie": f"tk_session_{live.port + 1}={live.token}"}
        assert request(live, "GET", "/snapshot", headers=other, token=False)[0] == 401
        assert request(live, "GET", "/snapshot", headers={"Cookie": "a=\"b"}, token=False)[0] == 401


def test_non_loopback_bind_is_refused(tmp):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        assert session.main(["--bind", "0.0.0.0", str(DEMO)]) == 2
    assert "127.0.0.1" in err.getvalue(), err.getvalue()
    shown = []
    with contextlib.redirect_stdout(out), testkit_home(tmp):
        assert session.main(["--bind", "127.0.0.1", str(DEMO)], wait=shown.append) == 0
    printed = out.getvalue()
    assert shown and printed.startswith(f"session: http://127.0.0.1:{shown[0].port}/?token={shown[0].token}"), printed


def test_static_serving_is_confined(tmp):
    with running(tmp) as live:
        assert request(live, "GET", "/viewer/index.html")[0] == 200
        for path in ("/viewer/../tools/session.py", "/%2e%2e/session.lua", "/session.lua", "/assets/../../x"):
            assert request(live, "GET", path)[0] == 404, path


def test_stream_says_hello_with_the_server_boot_id(tmp):
    with running(tmp) as live:
        boot = data_of(read_until(open_stream(live), "event: hello")[1])["boot"]
        assert isinstance(boot, str) and boot, boot
        assert data_of(read_until(open_stream(live), "event: hello")[1])["boot"] == boot
    with running(tmp) as other:
        assert data_of(read_until(open_stream(other), "event: hello")[1])["boot"] != boot


def test_stream_announces_changes(tmp):
    old = session_http.KEEPALIVE_SECONDS
    session_http.KEEPALIVE_SECONDS = 0.2
    try:
        with running(tmp) as live:
            stream = open_stream(live)
            read_until(stream, ": keepalive")
            assert request(live, "POST", "/fire", {"event": "PLAYER_REGEN_DISABLED"})[0] == 200
            _, data = read_until(stream, "event: snapshot")
            assert data_of(data)["seq"] > 0, data
    finally:
        session_http.KEEPALIVE_SECONDS = old


def test_bad_requests(tmp):
    with running(tmp) as live:
        status, _, body = request(live, "POST", "/fire", "{")
        assert status == 400 and json.loads(body)["ok"] is False, (status, body)
        assert request(live, "GET", "/nope")[0] == 404
        assert request(live, "DELETE", "/snapshot")[0] == 405


def test_json_nested_too_deep_is_a_bad_request(tmp):
    deep = "[" * 100000 + "]" * 100000
    with running(tmp) as live:
        status, _, body = request(live, "POST", "/fire", deep)
        assert status == 400 and json.loads(body)["error"].startswith("malformed request:"), (status, body[:200])
        status, reply = post_json(live, "/call/fire", deep)
        assert status == 200 and reply["ok"] is False and "too deep" in reply["error"], reply
        assert get_json(live, "/snapshot")["session"]["addon"] == "SessionDemo"


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


def test_dev_endpoint(tmp):
    with running(tmp, DEV_DEMO) as live:
        report = get_json(live, "/dev")
        addon = report["addons"][0]
        assert (report["ok"], addon["name"], len(addon["missing"])) == (True, "DevDemo", 2), report
        assert request(live, "POST", "/dev", {})[0] == 405


def test_run_cannot_reach_python(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        code = "/run print(type(python), type(__tk_fs), type(rawget(_G, 'python')), type(getfenv(0).__tk_fs))"
        assert post_json(live, "/slash", {"text": code}) == (200, {"ok": True, "handled": True})
        _, data = read_until(stream, "event: console")
        assert data_of(data)["text"] == "nil nil nil nil", data
    lua = run51.new_runtime()
    assert lua.execute("return python") is None
    for reach in ("return __tk_fs.list.__globals__", "__tk_fs.list.__doc__ = 'x'"):
        try:
            lua.execute(reach)
        except AttributeError:
            continue
        raise AssertionError(f"{reach!r} reached a private attribute")


TESTS = [
    test_snapshot_over_http,
    test_foreign_host_header_is_refused,
    test_cross_origin_and_wrong_content_type_are_refused,
    test_data_routes_need_the_token,
    test_token_url_sets_the_cookie_and_the_cookie_works,
    test_non_loopback_bind_is_refused,
    test_static_serving_is_confined,
    test_stream_says_hello_with_the_server_boot_id,
    test_stream_announces_changes,
    test_bad_requests,
    test_json_nested_too_deep_is_a_bad_request,
    test_call_relays_handle_json,
    test_located_outside_its_root_is_not_served,
    test_tree_and_frame_endpoints,
    test_state_and_events_endpoints,
    test_dev_endpoint,
    test_run_cannot_reach_python,
]

"""The session server's HTTP surface: routes, static files, the stream and /run's client globals (its guards are in
session_selftest_guard.py). Run through: python tools/session.py --selftest"""

import json

import run51
import session_host
import session_http
from session_selftest import COMBAT_DEMO, DEV_DEMO, data_of, get_json, item, open_stream, post_json, read_until, request, running


def test_snapshot_over_http(tmp):
    with running(tmp) as live:
        snapshot = get_json(live, "/snapshot")
        assert snapshot["ver"] == 1
        assert item(snapshot, "SessionDemoFrame")
        assert snapshot["session"]["addon"] == "SessionDemo"


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


def test_run_reads_no_host_bridge_global(tmp):
    """Client fidelity, not a security boundary (addon code is trusted): the client has no python or __tk_fs."""
    with running(tmp) as live:
        stream = open_stream(live)
        code = "/run print(type(python), type(__tk_fs), type(rawget(_G, 'python')), type(getfenv(0).__tk_fs))"
        assert post_json(live, "/slash", {"text": code}) == (200, {"ok": True, "handled": True})
        _, data = read_until(stream, "event: console")
        assert data_of(data)["text"] == "nil nil nil nil", data
    lua = run51.new_runtime()
    assert lua.execute("return python, package.loaded.python") == (None, None)
    for reach in ("return __tk_fs.list.__globals__", "__tk_fs.list.__doc__ = 'x'"):
        try:
            lua.execute(reach)
        except AttributeError:
            continue
        raise AssertionError(f"{reach!r} reached a private attribute")


def test_combat_play_pause_and_log(tmp):
    with running(tmp, COMBAT_DEMO) as live:
        stream = open_stream(live)

        def combat(req):
            status, reply = post_json(live, "/call/combat", req)
            assert status == 200, (status, reply)
            return reply

        assert combat({"action": "preset", "name": "dungeon"})["ok"] is True
        assert combat({"action": "pull"})["inCombat"] is True
        assert combat({"action": "step", "seconds": 3})["time"] == 3
        _, data = read_until(stream, "event: combatlog")
        assert data_of(data)["seq"] > 0, data
        status, log = post_json(live, "/call/combatlog", {"since": 0})
        assert status == 200 and log["ok"] and log["lines"], log
        assert combat({"action": "play", "speed": 2})["playing"] is True
        assert combat({"action": "pause"})["playing"] is False
        bad = combat({"action": "play", "speed": 3})
        assert bad["ok"] is False and "speed" in bad["error"], bad


def test_blizzard_reload_and_state_fields_are_checked(tmp):
    with running(tmp) as live:
        status, reply = post_json(live, "/reload", {"blizzardUi": "yes"})
        assert status == 400 and "blizzardUi" in reply["error"], (status, reply)
        assert get_json(live, "/snapshot")["session"]["loads"] == 1
        status, reply = post_json(live, "/state", {"actions": {"x": {}}})
        assert status == 400 and "'x'" in reply["error"], (status, reply)
        status, reply = post_json(live, "/state", {"editMode": {"active": 9}})
        assert status == 400 and "active" in reply["error"], (status, reply)
        status, reply = post_json(live, "/state", {"actions": {"3": {"texture": 7}}})
        assert status == 200 and reply["state"]["actions"] == {"3": {"texture": 7}}, (status, reply)
        assert get_json(live, "/snapshot")["session"]["blizzard"]["available"] is False


TESTS = [
    test_snapshot_over_http,
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
    test_run_reads_no_host_bridge_global,
    test_combat_play_pause_and_log,
    test_blizzard_reload_and_state_fields_are_checked,
]

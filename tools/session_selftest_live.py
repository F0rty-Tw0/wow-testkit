"""The live session through its server: input, the console stream, reloads (requested, by /reload, by the watcher),
assets and saved variables. Run through: python tools/session.py --selftest"""

import contextlib
import io
import time

from PIL import Image

import session
import session_host
from session_selftest import (
    CLICKY,
    DEMO,
    STREAM_WAIT,
    data_of,
    demo_copy,
    get_json,
    item,
    loads,
    open_stream,
    post_json,
    read_until,
    request,
    running,
    temp_addon,
    testkit_home,
    wait_for,
    wait_for_loads,
)


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


def test_console_events_stream(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        status, reply = post_json(live, "/slash", {"text": "/sdemo hi"})
        assert (status, reply) == (200, {"ok": True, "handled": True}), reply
        _, data = read_until(stream, "event: console")
        line = data_of(data)
        assert (line["kind"], line["text"]) == ("print", "slash hi"), line


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
        status, reply = post_json(live, "/reload", {"screen": {"width": 100, "height": 100}})
        assert (status, reply["ok"]) == (400, False) and "screen" in reply["error"], (status, reply)
        after = get_json(live, "/snapshot")
        assert after["session"] == before["session"] and after["screen"] == before["screen"], after["session"]
        assert post_json(live, "/slash", {"text": "/sdemo alive"}) == (200, {"ok": True, "handled": True})


def test_reload_event_is_streamed(tmp):
    with running(tmp) as live:
        stream = open_stream(live)
        assert post_json(live, "/reload", {})[1]["ok"] is True
        _, data = read_until(stream, "event: reload")
        assert data_of(data) == {"loads": 2}, data


def test_assets_resolve_and_are_served(tmp):
    with running(tmp, temp_addon(tmp)) as live:
        asset = get_json(live, "/snapshot")["assets"]["path:interface/addons/t/pic"]
        assert asset["source"] == "addon" and asset["url"].startswith("assets/"), asset
        status, content_type, _ = request(live, "GET", "/" + asset["url"])
        assert (status, content_type) == (200, "image/png")
        status, snapshot = post_json(live, "/call/snapshot", {})
        asset = snapshot["assets"]["path:interface/addons/t/pic"]
        assert status == 200 and asset["source"] == "addon" and "url" in asset, asset


def test_slash_reload_serves_changed_assets(tmp):
    root = temp_addon(tmp)
    with running(tmp, root) as live:
        url = get_json(live, "/snapshot")["assets"]["path:interface/addons/t/pic"]["url"]
        Image.new("RGBA", (2, 2), (0, 0, 255, 255)).save(root / "pic.png")
        assert post_json(live, "/slash", {"text": "/reload"}) == (200, {"ok": True, "handled": True})
        assert get_json(live, "/snapshot")["session"]["loads"] == 2
        _, _, body = request(live, "GET", "/" + url)
        assert Image.open(io.BytesIO(body)).getpixel((0, 0)) == (0, 0, 255, 255)


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
            if data_of(data)["text"] == "2":
                break
            assert time.time() < deadline, "no console line 2"


def test_a_failed_watched_reload_is_reported(tmp):
    root = demo_copy(tmp)
    err = io.StringIO()
    with running(tmp, root, watch=True) as live, contextlib.redirect_stderr(err):
        live.host.call = lambda method, req: {"ok": False, "error": "no world"}
        time.sleep(0.6)  # one poll interval: the watcher's first scan must see the file before the edit
        (root / "Main.lua").write_text("-- edited\n", encoding="utf-8")
        assert wait_for(lambda: "reload failed: no world" in err.getvalue()), err.getvalue()


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


def test_shutdown_writes_the_file(tmp):
    with testkit_home(tmp):
        live = session.start(str(DEMO), port=0)
        live.stop()
        saved = session_host.session_dir_for(DEMO) / "saved.lua"
        assert saved.is_file() and "runs = 1" in saved.read_text(encoding="utf-8"), saved


TESTS = [
    test_input_fire_slash_state_round_trip,
    test_point_click_over_http,
    test_press_wheel_drag_over_http,
    test_console_events_stream,
    test_reload_keeps_the_server_up,
    test_reload_flavor_and_size_over_http,
    test_reload_event_is_streamed,
    test_assets_resolve_and_are_served,
    test_slash_reload_serves_changed_assets,
    test_file_save_reloads_and_keeps_saved_variables,
    test_a_failed_watched_reload_is_reported,
    test_unwatched_file_changes_do_not_reload,
    test_several_quick_saves_reload_once,
    test_shutdown_writes_the_file,
]

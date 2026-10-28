"""The session server's guards: the Host/Origin/content-type checks, the session token and its cookie (kept across a
restart), the bind address, the Referrer-Policy header and the connection cap. Run through: python tools/session.py
--selftest"""

import contextlib
import http.client
import io
import json
import os
import socket
import time

import session
import session_files
import session_http
from session_selftest import DEMO, STREAM_WAIT, data_of, get_json, open_stream, read_until, request, running, testkit_home, wait_for


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


def test_restart_on_the_same_port_keeps_the_cookie_and_says_a_new_boot(tmp):
    with running(tmp) as first:
        port, token = first.port, first.token
        boot = data_of(read_until(open_stream(first), "event: hello")[1])["boot"]
    with running(tmp, port=port) as second:
        assert second.token == token
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=STREAM_WAIT)
        conn.request("GET", "/stream", headers={"Cookie": f"tk_session_{port}={token}"})
        stream = conn.getresponse()
        assert stream.status == 200, stream.status
        assert data_of(read_until(stream, "event: hello")[1])["boot"] != boot
        path = second.host.session_dir / session_files.TOKEN_FILE
    assert path.read_text(encoding="ascii") == token
    if os.name == "posix":
        assert path.stat().st_mode & 0o077 == 0, oct(path.stat().st_mode)
    path.write_text("not a token", encoding="ascii")
    fresh = session_files.session_token(path.parent)
    assert fresh != token and session_files.TOKEN_SHAPE.match(fresh), fresh


def test_a_refused_request_with_the_token_sets_no_cookie(tmp):
    with running(tmp) as live:
        for headers in ({"Origin": "http://evil.example"}, {"Host": "evil.example"}):
            conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=10)
            conn.request("GET", "/?token=" + live.token, headers=headers)
            reply = conn.getresponse()
            conn.close()
            assert (reply.status, reply.getheader("Set-Cookie")) == (403, None), (headers, reply.status)


def test_every_reply_says_no_referrer(tmp):
    with running(tmp) as live:
        for method, path, token in (
            ("GET", "/snapshot", True),
            ("GET", "/?token=" + live.token, False),
            ("GET", "/snapshot", False),
            ("GET", "/nope", True),
            ("GET", "/viewer/index.html", False),
            ("PUT", "/snapshot", True),
            ("FOO", "/snapshot", True),
            ("GET", "/stream", True),
        ):
            conn = http.client.HTTPConnection("127.0.0.1", live.port, timeout=STREAM_WAIT)
            conn.request(method, path, headers={"X-Session-Token": live.token} if token else {})
            policy = conn.getresponse().getheader("Referrer-Policy")
            conn.close()
            assert policy == "no-referrer", (method, path, policy)


def _trickler(port):
    """A connection that sends a request line and then a header line now and then, never finishing its headers."""
    sock = socket.create_connection(("127.0.0.1", port), timeout=STREAM_WAIT)
    sock.sendall(f"GET /snapshot HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n".encode("ascii"))

    return sock


def _status(live):
    """The status of GET /snapshot, or None when the server closes the connection unanswered."""
    try:
        return request(live, "GET", "/snapshot")[0]
    except (ConnectionError, http.client.HTTPException):
        return None


def test_connections_past_the_cap_are_closed_unanswered(tmp):
    old = session_http.MAX_CONNECTIONS
    session_http.MAX_CONNECTIONS = 2
    try:
        with running(tmp) as live:
            slow = [_trickler(live.port), _trickler(live.port)]
            for _ in range(3):
                time.sleep(0.2)
                for sock in slow:
                    sock.sendall(b"X-Slow: 1\r\n")
            assert _status(live) is None
            for sock in slow:
                sock.sendall(b"\r\n")
                while sock.recv(4096):
                    pass
                sock.close()
            assert wait_for(lambda: _status(live) == 200)
    finally:
        session_http.MAX_CONNECTIONS = old


def test_blizzard_flag_is_accepted_and_needs_an_extract(tmp):
    assert session._parser().parse_args(["--blizzard-ui", str(DEMO)]).blizzard_ui is True
    assert session._parser().parse_args([str(DEMO)]).blizzard_ui is False
    with testkit_home(tmp), contextlib.redirect_stderr(io.StringIO()) as err:
        assert session.main(["--blizzard-ui", str(DEMO)], wait=lambda running: None) == 2
    assert "--blizzard-ui needs --extract" in err.getvalue()


def test_blizzard_flag_loads_the_layer_from_the_extract(tmp):
    """A kit-authored mini extract: one "Blizzard" addon under a default target's folder name."""
    extract = tmp / "client" / "retail" / "70575"
    addon = extract / "code" / "addons" / "blizzard_actionbar"
    addon.mkdir(parents=True)
    (extract / "manifest.lua").write_text('return { product = "wow", flavor = "retail", build = "70575", locales = { "enUS" } }')
    (addon / "blizzard_actionbar.toc").write_text("MiniPy.lua\n")
    (addon / "minipy.lua").write_text('CreateFrame("Frame", "MiniPy", UIParent)\n')
    with testkit_home(tmp):
        live = session.start(str(DEMO), port=0, extract=str(extract), blizzard_ui=True)
        try:
            layer = get_json(live, "/snapshot")["session"]["blizzard"]
        finally:
            live.stop()
    assert layer["enabled"] is True and layer["loaded"] == ["Blizzard_ActionBar"], layer


def test_wtf_flags_are_usage_checked(tmp):
    cases = [
        (["--wtf", str(tmp / "missing")], "--wtf: no such directory"),
        (["--wtf-account", "A"], "--wtf-account needs --wtf"),
        (["--wtf", str(tmp), "--wtf-character", "NoRealm"], "--wtf-character must be REALM/CHARACTER"),
    ]
    for flags, needle in cases:
        with testkit_home(tmp), contextlib.redirect_stderr(io.StringIO()) as err:
            assert session.main(flags + [str(DEMO)], wait=lambda running: None) == 2, flags
        assert needle in err.getvalue(), (flags, err.getvalue())


def test_wtf_flag_imports_and_confines_reimport(tmp):
    """A synthetic WTF folder: its SessionDemo file seeds the session; a reimport path outside the folder is refused."""
    wtf = tmp / "WTF"
    saved = wtf / "Account" / "ACC" / "SavedVariables"
    saved.mkdir(parents=True)
    (saved / "SessionDemo.lua").write_text("SessionDemoDB = { runs = 40 }\n")
    outside = tmp / "outside.lua"
    outside.write_text("SessionDemoDB = { runs = 1 }\n")
    with testkit_home(tmp):
        live = session.start(str(DEMO), port=0, wtf=str(wtf))
        try:
            status, _, body = request(live, "POST", "/call/reimport", {"wtf": {"account": str(outside)}})
            refused = json.loads(body)
            status2, _, body2 = request(live, "POST", "/call/reimport", {"wtf": {"account": str(wtf / ".." / "outside.lua")}})
            climbed = json.loads(body2)
            live.host.call("slash", {"text": "/dump SessionDemoDB.runs"})
            last = live.host.call("console", {"since": 0})["lines"][-1]["text"]
        finally:
            live.stop()
    assert status == 200 and refused == {"ok": False, "error": "malformed request: wtf paths must stay inside the WTF folder"}, refused
    assert status2 == 200 and climbed["ok"] is False, climbed
    assert last == "41", last
    assert sorted(p.name for p in wtf.rglob("*")) == ["ACC", "Account", "SavedVariables", "SessionDemo.lua"]
    assert (saved / "SessionDemo.lua").read_text() == "SessionDemoDB = { runs = 40 }\n"


TESTS = [
    test_foreign_host_header_is_refused,
    test_cross_origin_and_wrong_content_type_are_refused,
    test_data_routes_need_the_token,
    test_token_url_sets_the_cookie_and_the_cookie_works,
    test_non_loopback_bind_is_refused,
    test_restart_on_the_same_port_keeps_the_cookie_and_says_a_new_boot,
    test_a_refused_request_with_the_token_sets_no_cookie,
    test_every_reply_says_no_referrer,
    test_connections_past_the_cap_are_closed_unanswered,
    test_blizzard_flag_is_accepted_and_needs_an_extract,
    test_blizzard_flag_loads_the_layer_from_the_extract,
    test_wtf_flags_are_usage_checked,
    test_wtf_flag_imports_and_confines_reimport,
]

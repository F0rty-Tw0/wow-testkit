"""Tests for listfile and probe."""

import contextlib
import hashlib
import io
import json

from tools.client import listfile, probe
from tools.client.fakes import FakeCasc

NAMES = {
    1: "interface/addons/blizzard_a/a.lua",
    2: "interface/buttons/white8x8.blp",
    3: "dbfilesclient/uitextureatlas.db2",
    4: "fonts/frizqt__.ttf",
}
API_URL = "https://api.github.com/repos/wowdev/wow-listfile/releases/latest"
RELEASE = {
    "tag_name": "202610240000",
    "assets": [{"name": "community-listfile.csv", "browser_download_url": "https://x/lf.csv"}],
}


def test_listfile_load_lowercases_and_skips_bad_lines(tmp):
    p = tmp / "lf.csv"
    p.write_text("100;Interface/Buttons/WHITE8X8.blp\nbad line\n;x\n101;Fonts\\FRIZQT__.TTF\n")
    assert listfile.load(p) == {100: "interface/buttons/white8x8.blp", 101: "fonts/frizqt__.ttf"}


def test_probe_checks_magic_per_file_type(tmp):
    store = FakeCasc({1: b"-- lua\nx=1\n", 2: b"BLP2....", 3: b"WDC5....", 4: b"\x00\x01\x00\x00.."})
    assert [r.ok for r in probe.run_probes(store, NAMES)] == [True, True, True, True]


def test_probe_fails_on_wrong_magic_or_missing_file(tmp):
    store = FakeCasc({2: b"JUNK....", 3: b"WDC5...."})  # blp wrong magic, lua and ttf ids absent
    results = probe.run_probes(store, NAMES)
    assert {r.name: r.ok for r in results} == {"lua": False, "blp": False, "db2": True, "ttf": False}


def test_listfile_fetch_records_tag_and_hash(tmp):
    body = b"1;a\n"
    answers = {API_URL: json.dumps(RELEASE).encode(), "https://x/lf.csv": body}
    seen = []

    def opener(request):
        seen.append(request.full_url)
        return io.BytesIO(answers[request.full_url])

    dest = tmp / "sub" / "lf.csv"
    info = listfile.fetch(dest, opener=opener)
    assert info == {"source": "wowdev/wow-listfile", "tag": "202610240000", "sha256": hashlib.sha256(body).hexdigest()}
    assert dest.read_bytes() == body
    assert seen == [API_URL, "https://x/lf.csv"]


def test_unknown_candidate_exits_3_and_names_it(tmp):
    err = io.StringIO()
    argv = ["--candidate", "nope", "--install", str(tmp), "--products", "wow", "--listfile", str(tmp / "lf.csv")]
    with contextlib.redirect_stderr(err):
        code = probe.main(argv)
    assert code == 3
    assert "candidate 'nope' not available" in err.getvalue()


TESTS = [
    test_listfile_load_lowercases_and_skips_bad_lines,
    test_probe_checks_magic_per_file_type,
    test_probe_fails_on_wrong_magic_or_missing_file,
    test_listfile_fetch_records_tag_and_hash,
    test_unknown_candidate_exits_3_and_names_it,
]

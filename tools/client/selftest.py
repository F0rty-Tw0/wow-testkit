"""Runs tools/client/selftest_<area>.py files. Run from the repo root: python -m tools.client.selftest [area]"""

import contextlib
import importlib
import os
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent


def areas(wanted):
    found = sorted(path.stem[len("selftest_") :] for path in HERE.glob("selftest_*.py"))
    return [name for name in found if wanted is None or name == wanted]


@contextlib.contextmanager
def sealed_env():
    """No test may read the install or a real extract."""
    saved = {key: os.environ.get(key) for key in ("TESTKIT_HOME", "TESTKIT_WOW_DIR")}
    with tempfile.TemporaryDirectory() as home:
        os.environ["TESTKIT_HOME"] = home
        os.environ["TESTKIT_WOW_DIR"] = str(Path(home) / "no-wow-install")
        try:
            yield
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


def run_one(test):
    with tempfile.TemporaryDirectory() as tmp:
        test(Path(tmp))


def run(wanted=None):
    passed = failed = 0
    with sealed_env():
        for area in areas(wanted):
            module = importlib.import_module(f"tools.client.selftest_{area}")
            for test in module.TESTS:
                try:
                    run_one(test)
                    print("PASS " + test.__name__)
                    passed += 1
                except Exception:
                    print("FAIL " + test.__name__)
                    traceback.print_exc()
                    failed += 1
    print(f"{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else None))

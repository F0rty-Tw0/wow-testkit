"""API writer: the extract's own API docs (code/addons/blizzard_apidocumentationgenerated) -> <out>/api.lua.

Runs after the code writer and reads only what it wrote; the Lua side (tools/client_api.lua, on Lua 5.1 via
tools/run51.py) loads the docs with tools/docs.lua. The kit fills the result into a world's Enum and Constants.
"""

import subprocess
import sys
from pathlib import Path

DOCS = Path("code/addons/blizzard_apidocumentationgenerated")
KIT_ROOT = Path(__file__).resolve().parents[2]
NO_DOCS_NOTE = "api: no API docs in the code extract; run --what code first"


def write(source, out, ctx):
    """Writes <out>/api.lua; returns its table count (enums incl. <Name>Meta, plus constants). `source` is unused."""
    from tools.client.extract import ExtractError  # extract.py imports this module: a top-level import is circular

    if not (Path(out) / DOCS).is_dir():
        ctx.notes.append(NO_DOCS_NOTE)
        return 0
    command = [sys.executable, "tools/run51.py", "--script", "tools/client_api.lua", Path(out).as_posix()]
    done = subprocess.run(command, cwd=KIT_ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        tail = "\n".join(done.stderr.strip().splitlines()[-5:])
        raise ExtractError(f"api: {tail}")
    return int(done.stdout.strip().splitlines()[-1])

"""What the session server reads from disk: the static files it serves, confined to their root, and the session's
token, kept in the session folder so a restarted server accepts the cookie its viewer holds."""

import os
import re
import secrets
from pathlib import Path
from urllib.parse import unquote

TOKEN_FILE = "token"
TOKEN_SHAPE = re.compile(r"^[A-Za-z0-9_-]{32}$")
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}


def static_file(root, relative):
    """The file under root that the url remainder names, or None unless its real path stays inside root."""
    relative = unquote(relative)
    if not relative or "\0" in relative or ":" in relative:
        return None
    real_root = os.path.realpath(root)
    target = os.path.realpath(os.path.join(real_root, relative))
    try:
        inside = os.path.commonpath([real_root, target]) == real_root
    except ValueError:  # another drive
        return None
    return Path(target) if inside and os.path.isfile(target) else None


def content_type(path):
    return CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream")


def session_token(session_dir):
    """The token <session_dir>/token holds, made and saved there first when it holds none, so a server restarted on the
    same session keeps the cookie its viewer has. The file is made readable by this user only where the OS honours the
    mode (POSIX); on Windows it inherits the folder's access list (the testkit home, under the user's profile)."""
    path = Path(session_dir) / TOKEN_FILE
    try:
        saved = path.read_text(encoding="ascii").strip()
    except (OSError, UnicodeDecodeError):
        saved = ""
    if TOKEN_SHAPE.match(saved):
        return saved
    token = secrets.token_urlsafe(24)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="ascii") as out:
        out.write(token)
    os.chmod(path, 0o600)

    return token

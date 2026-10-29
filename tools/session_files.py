"""What the session server reads from disk: the static files it serves, confined to their root, and the session's
token, kept in the session folder for a day so a restarted server accepts the cookie its viewer holds."""

import os
import re
import secrets
import stat
import time
from pathlib import Path
from urllib.parse import unquote

TOKEN_FILE = "token"
TOKEN_SHAPE = re.compile(r"^[A-Za-z0-9_-]{32}$")
TOKEN_MAX_AGE = 24 * 60 * 60  # seconds a saved token is reused before a restart rotates it
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


def reusable(info, now, uid):
    """True when a saved token file (its lstat) may be reused: a regular file, not a link, saved less than
    TOKEN_MAX_AGE ago and, where uid is given (POSIX), owned by uid and closed to group and others. A token another
    user could read or plant would let them drive the session, and its /run executes code as this user."""
    fresh = stat.S_ISREG(info.st_mode) and 0 <= now - info.st_mtime < TOKEN_MAX_AGE
    if not fresh or uid is None:
        return fresh

    return info.st_uid == uid and not info.st_mode & 0o077


def _saved_token(path):
    """The token a reusable file at path holds, or None."""
    uid = os.getuid() if hasattr(os, "getuid") else None
    now = time.time()
    try:
        if not reusable(os.lstat(path), now, uid):
            return None
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))  # POSIX: a link swapped in since fails here
        with os.fdopen(fd, encoding="ascii") as saved_file:
            if not reusable(os.fstat(saved_file.fileno()), now, uid):  # the file read is the file checked
                return None
            saved = saved_file.read().strip()
    except (OSError, UnicodeDecodeError):
        return None

    return saved if TOKEN_SHAPE.match(saved) else None


def session_token(session_dir):
    """The token <session_dir>/token holds, so a server restarted on the same session keeps the cookie its viewer has.
    A file `reusable` refuses (a link, another user's, open to others, a day old) or a malformed one is replaced by a
    fresh token: the old file is removed and the new one made exclusively, so a planted link is never followed. The
    file is readable by this user only where the OS honours the mode (POSIX); on Windows it inherits the folder's
    access list (the testkit home, under the user's profile)."""
    path = Path(session_dir) / TOKEN_FILE
    saved = _saved_token(path)
    if saved:
        return saved
    token = secrets.token_urlsafe(24)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:  # another server on this session saved one between the unlink and the open
        saved = _saved_token(path)
        if saved:
            return saved
        raise
    with os.fdopen(fd, "w", encoding="ascii") as out:
        out.write(token)

    return token

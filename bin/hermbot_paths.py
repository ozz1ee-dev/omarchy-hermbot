#!/usr/bin/env python3
"""Where things live on THIS machine.

The watcher, the opener and the sender must agree on four directories, and on
somebody else's machine any of them may be somewhere else. So they are resolved
in one place, from the same environment that the shell, Hermes and Electron
themselves read:

  HERMES_HOME      Hermes' own home. hermes_cli reads it (`home =
                   os.environ.get("HERMES_HOME")` else ~/.hermes) and the desktop
                   passes it to the backends it spawns, so an install that moved
                   must not be read as a stock ~/.hermes.
  XDG_STATE_HOME   Omarchy's own plugins resolve their state as
                   ${XDG_STATE_HOME:-~/.local/state}; ours follows, so a user who
                   moved it keeps everything together.
  XDG_CONFIG_HOME  Electron honours it, so Hermes Desktop's registry lands there
                   on machines that set it.

Nothing here names a user or an install path: the scripts find each other through
__file__, so the plugin works from any directory it is installed into.
"""
import os
import stat
from pathlib import Path


def env_dir(var):
    """The directory named by an environment variable, or None when unset."""
    value = os.environ.get(var)
    return Path(value).expanduser() if value else None


HOME = Path.home()
HERMES_HOME = env_dir("HERMES_HOME") or (HOME / ".hermes")


def _resolve_root(candidate):
    """A Hermes *home*, even when the variable names one profile.

    HERMES_HOME normally names the home (it holds `config.yaml` and `profiles/`),
    but a process Hermes started inside one profile gets it pinned to that
    profile's directory instead ("-p <name> or pin HERMES_HOME to the profile
    dir" in hermes_cli). The roster lives at the home, so a profile directory
    resolves up to its parent - and anything else is taken as it stands, because
    an install without a `profiles/` directory (a single-profile gateway, for
    instance) is a legitimate home too.
    """
    try:
        if (candidate / "profiles").is_dir():
            return candidate
        if (candidate / "profile.yaml").exists() and candidate.parent.name == "profiles":
            return candidate.parent.parent
    except OSError:
        pass
    return candidate


ROOT = _resolve_root(HERMES_HOME)
STATE_DIR = (env_dir("XDG_STATE_HOME") or (HOME / ".local/state")) / "omarchy" / "hermbot"


def appdata():
    """Hermes Desktop's state directory, wherever this machine keeps it.

    Prefer whichever candidate actually holds a registry - a machine that set
    XDG_CONFIG_HOME after first running the app can have both - and otherwise
    name the one the app would write to.
    """
    candidates = [(env_dir("XDG_CONFIG_HOME") or (HOME / ".config")) / "Hermes"]
    plain = HOME / ".config" / "Hermes"
    if plain != candidates[0]:
        candidates.append(plain)
    for cand in candidates:
        if (cand / "connections.json").exists() or (cand / "connection.json").exists():
            return cand
    return candidates[0]


APPDATA = appdata()


def open_nofollow(path, flags, mode=0o600):
    """`os.open` that refuses to follow a symlink at `path`.

    O_NOFOLLOW makes a symlink an error (ELOOP) instead of a door: without it a
    pre-created link at a predictable name, in a directory somebody else can
    write to, redirects the open - and a truncating open then destroys whatever it
    was pointed at. Ownership and type are checked on the opened descriptor, not
    on the name, so nothing can be swapped underneath between the two.
    """
    fd = os.open(path, flags | os.O_NOFOLLOW, mode)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        os.close(fd)
        raise OSError("refusing %s: not a regular file we own" % path)
    return fd


def _create_exclusive(tmp):
    """Create a fixed temporary name with O_EXCL, clearing only our own leftover.

    A crashed run can leave the temporary behind, and that one is ours to remove -
    but anything at that name which is not a regular file we own (a symlink, a
    directory, somebody else's file) is refused rather than replaced, because that
    is exactly the shape of the attack this guards against.
    """
    for _ in range(2):
        try:
            return open_nofollow(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        except FileExistsError:
            try:
                info = os.lstat(tmp)
            except OSError:
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                raise OSError("refusing to clear %s: not a regular file we own" % tmp)
            os.unlink(tmp)
    raise OSError("could not create %s" % tmp)


def atomic_write(path, data, encoding=None):
    """Replace `path` with `data`, never writing through a pre-made entry.

    A plain write to a fixed temporary name follows whatever already sits there,
    and in a directory others can write to that is a symlink aimed at any file this
    account may write - the update then lands on the attacker's target. Creating
    the temporary with O_EXCL and swapping it in with a rename closes that: an
    existing name can only be refused or cleared, never followed or reused, and the
    rename replaces the destination entry itself rather than what it points at.
    Pass `encoding` for text, or leave it None for bytes.
    """
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    fd = _create_exclusive(tmp)
    try:
        kwargs = {} if encoding is None else {"encoding": encoding}
        with os.fdopen(fd, "wb" if encoding is None else "w", **kwargs) as fh:
            fh.write(data)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    os.replace(tmp, path)


# The three logs under the state directory (open.log, send.log, notify.log) are
# written on every open, every send and every notification, and nothing ever reads
# them back - they exist so a user can see what the widget did. Left alone they
# grow for as long as the bar runs, on a file nobody prunes. So they are capped:
# past LOG_CAP the file keeps only its last LOG_KEEP_BYTES, trimmed to a line
# boundary. That preserves the recent history (the part anyone actually looks at)
# and bounds the file. A failure here is never worth taking a caller down for.
LOG_CAP_BYTES = 256 * 1024
LOG_KEEP_BYTES = 128 * 1024


def append_log(path, line):
    """Append one already-formatted line, trimming the log to its tail past the cap.

    Callers own the line format (one of them carries no timestamp), so this only
    appends and bounds - it never rewrites what a log line looks like. Both halves
    go through the no-follow helpers: an append is as easy to redirect through a
    pre-created symlink as a truncating write, and the trim is a replace.
    """
    try:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd = open_nofollow(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(str(line).rstrip() + "\n")
        if path.stat().st_size <= LOG_CAP_BYTES:
            return
        tail = path.read_bytes()[-LOG_KEEP_BYTES:]
        # Never start on a half-written line left by the trim itself.
        cut = tail.find(b"\n")
        if cut >= 0:
            tail = tail[cut + 1:]
        atomic_write(path, tail)
    except (OSError, ValueError):
        pass

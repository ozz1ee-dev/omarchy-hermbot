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

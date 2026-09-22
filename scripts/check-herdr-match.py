#!/usr/bin/env python3
"""The Herdr jump must match a conversation by its exact session id.

Regression guard for the "it opened the wrong thread" bug: the matcher used to
fall back to the profile, so a session that was not running focused whichever
pane of that profile happened to exist - a different conversation. It must report
"not running" instead, so the caller opens the exact session. Run: this exits 0
when the rule holds, 1 with a reason when it does not.
"""
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("hermbot_herdr", str(ROOT / "bin" / "hermbot-herdr"))
_spec = importlib.util.spec_from_loader("hermbot_herdr", _loader)
herdr = importlib.util.module_from_spec(_spec)
_loader.exec_module(herdr)

# One dev pane, running one specific dev session.
AGENTS = [{"pane_id": "w3:pF", "tab_id": "w3:tF",
           "terminal_title": "hermes -p dev chat -c 20260922_223639_007ea8"}]


def main():
    failures = []
    # A dev session that is not running must not be "found" in another dev pane.
    if herdr.match_agent(AGENTS, "20260906_025654_dd8a98") is not None:
        failures.append("a not-running dev session matched a different dev pane")
    # The exact running session is found, and points at its pane.
    found = herdr.match_agent(AGENTS, "20260922_223639_007ea8")
    if not found or found.get("pane_id") != "w3:pF":
        failures.append("the running session was not found")
    # Nothing to look for matches nothing.
    if herdr.match_agent(AGENTS, "") is not None:
        failures.append("an empty session matched")
    for reason in failures:
        print("FAIL  " + reason)
    if failures:
        return 1
    print("OK: the Herdr jump matches by exact session id only")
    return 0


if __name__ == "__main__":
    sys.exit(main())

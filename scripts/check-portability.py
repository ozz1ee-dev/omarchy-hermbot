#!/usr/bin/env python3
"""Prove the plugin adapts to a machine that is not ours.

Builds a throwaway "foreign" world in a temp directory - a different home, a
Hermes install somewhere else entirely (HERMES_HOME), state and config moved by
XDG_* - and runs the watcher inside it with a CLEAN environment, so nothing from
whoever runs this test can leak in. Then the negative cases: a machine with no
Hermes at all, and a HERMES_HOME that names one profile instead of the home.

Run it anywhere with python3 (no Omarchy, no Hermes, no network):

    python3 scripts/check-portability.py

Exit code 0 = every case behaved as documented.
"""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import io
import base64
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WATCH = ROOT / "bin" / "hermbot-watch"

FAILURES = []


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{(' - ' + detail) if detail else ''}")
    if not ok:
        FAILURES.append(name)


def run(env_extra, args=("--once",)):
    """Run the watcher with a clean environment plus `env_extra`."""
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    env.update(env_extra)
    proc = subprocess.run([sys.executable, str(WATCH), *args], env=env,
                          capture_output=True, text=True, timeout=90)
    snapshot = None
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            snapshot = json.loads(line)
            break
    return proc, snapshot


def profile(title, shape, color):
    return (f"description: {title}\n"
            "ui_meta:\n"
            "  hermes-bots:\n"
            f"    shape: {shape}\n"
            f"    color: {color}\n"
            f"    title: {title}\n"
            "    imageKind: shape\n"
            "    custom: true\n")


def build_world(base):
    """A home that looks nothing like a stock install, with three bots."""
    home = base / "home"
    hermes = base / "opt" / "hermes-data"
    (hermes / "profiles" / "alpha").mkdir(parents=True)
    (hermes / "profiles" / "beta").mkdir(parents=True)
    (hermes / "profiles" / "sessions").mkdir(parents=True)     # infra: never a bot
    (base / "var" / "state").mkdir(parents=True)
    (base / "etc" / "Hermes").mkdir(parents=True)
    (hermes / "config.yaml").write_text("display:\n  interface: tui\n")
    (hermes / "profile.yaml").write_text(profile("Recap Bot", "sun", '"hsl(200 70% 55%)"'))
    (hermes / "profiles" / "alpha" / "profile.yaml").write_text(
        profile("Bug Triager", "blobatar::round", '"hsl(120 60% 45%)"'))
    (hermes / "profiles" / "beta" / "profile.yaml").write_text(
        profile("Notes Droid", "cloud", "null"))
    (hermes / "state.db").touch()                              # marker only
    (base / "etc" / "Hermes" / "connections.json").write_text(json.dumps({
        "version": 2, "primary": "local", "launchMode": "primary", "lastUsed": "build-box",
        "connections": [
            {"id": "local", "kind": "local", "label": "This device"},
            {"id": "build-box", "kind": "remote", "label": "Build box",
             "url": "https://example.invalid:9119"}]}))
    return home, hermes


def main():
    base = Path(tempfile.mkdtemp(prefix="hermbot-portability-"))
    try:
        home, hermes = build_world(base)
        env = {"HOME": str(home), "HERMES_HOME": str(hermes),
               "XDG_STATE_HOME": str(base / "var" / "state"),
               "XDG_CONFIG_HOME": str(base / "etc")}

        print("foreign machine")
        proc, snap = run(env)
        names = sorted(b["name"] for b in (snap or {}).get("bots", []))
        check("exit 0", proc.returncode == 0, f"rc={proc.returncode}")
        check("nothing on stderr", not proc.stderr.strip(), proc.stderr.strip()[:120])
        check("three bots from HERMES_HOME", names == ["alpha", "beta", "default"], str(names))
        titles = {b["name"]: b["title"] for b in (snap or {}).get("bots", [])}
        check("titles come from the other install",
              titles.get("alpha") == "Bug Triager" and titles.get("default") == "Recap Bot",
              str(titles))
        check("infra dir is not a bot", "sessions" not in names)
        check("@{handle} follows the app's own rule",
              {b["name"]: b["handle"] for b in (snap or {}).get("bots", [])} ==
              {"default": "@hermes", "alpha": "@alpha", "beta": "@beta"})
        state = base / "var" / "state" / "omarchy" / "hermbot" / "notify.json"
        check("state follows XDG_STATE_HOME", state.exists(), str(state))
        check("registry read from XDG_CONFIG_HOME",
              (snap or {}).get("source_warning") == "Build box (remote)",
              repr((snap or {}).get("source_warning")))

        print("foreign machine, no Hermes at all")
        proc, snap = run({"HOME": str(home), "XDG_STATE_HOME": str(base / "var" / "state")})
        check("says so instead of a phantom bot",
              (snap or {}).get("error") == "no Hermes install here" and not snap.get("bots"),
              repr((snap or {}).get("error")))
        check("still exits 0", proc.returncode == 0, f"rc={proc.returncode}")

        print("HERMES_HOME pinned to a profile directory")
        proc, snap = run({**env, "HERMES_HOME": str(hermes / "profiles" / "alpha")})
        names = sorted(b["name"] for b in (snap or {}).get("bots", []))
        check("resolves up to the home", names == ["alpha", "beta", "default"], str(names))

        print("the bundle sent to another machine")
        sys.path.insert(0, str(ROOT / "bin"))
        from importlib.machinery import SourceFileLoader
        import types
        # The scripts have no .py suffix on purpose (they are executables), so the
        # loader is named explicitly rather than inferred from the filename.
        loader = SourceFileLoader("hermbot_watch_probe", str(WATCH))
        module = types.ModuleType(loader.name)
        module.__file__ = str(WATCH)   # the scripts resolve siblings from this
        loader.exec_module(module)
        payload = module._remote_payload()
        blob = payload.split("blob = ", 1)[1].split("\n", 1)[0].strip("'\"")
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(blob))) as tar:
            members = sorted(m.name for m in tar.getmembers())
        check("carries every file the far side imports",
              members == ["hermbot-watch", "hermbot_paths.py"], str(members))
    finally:
        shutil.rmtree(base, ignore_errors=True)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} case(s) failed: {', '.join(FAILURES)}")
        return 1
    print("every case behaved as documented")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check the plugin folder without needing Omarchy installed.

Mirrors what `omarchy plugin validate` enforces for a bar-widget: the manifest
parses, the required fields are there, the declared kind has an entry point, that
file exists, the id is namespaced and not first-party, and the folder holds no
symlinks.

    python3 scripts/check-manifest.py [plugin-dir]
"""

import json
import os
import sys

REQUIRED = ("schemaVersion", "id", "name", "version", "author", "description", "kinds", "entryPoints")
ENTRY_KEYS = {
    "bar-widget": "barWidget",
    "panel": "panel",
    "overlay": "overlay",
    "menu": "menu",
    "service": "service",
    "bar": "bar",
}


def fail(message):
    print("FAIL: %s" % message)
    return 1


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    problems = []

    manifest_path = os.path.join(root, "manifest.json")
    if not os.path.isfile(manifest_path):
        sys.exit(fail("no manifest.json in %s" % root))

    try:
        with open(manifest_path) as handle:
            manifest = json.load(handle)
    except ValueError as error:
        sys.exit(fail("manifest.json is not valid JSON: %s" % error))

    for field in REQUIRED:
        if not manifest.get(field):
            problems.append("manifest is missing %s" % field)

    plugin_id = str(manifest.get("id", ""))
    if plugin_id:
        if "." not in plugin_id:
            problems.append("id %r is not namespaced (expected author.plugin)" % plugin_id)
        if plugin_id.startswith("omarchy."):
            problems.append("id %r uses the reserved omarchy. namespace" % plugin_id)
    if len(str(manifest.get("version", ""))) > 64:
        problems.append("version is longer than 64 characters")

    entry_points = manifest.get("entryPoints") or {}
    if not isinstance(entry_points, dict):
        problems.append("entryPoints must be an object")
        entry_points = {}

    for kind in manifest.get("kinds") or []:
        key = ENTRY_KEYS.get(kind)
        if not key:
            problems.append("unknown kind %r" % kind)
            continue
        path = str(entry_points.get(key, ""))
        if not path:
            problems.append("kind %r has no entryPoints.%s" % (kind, key))
            continue
        if os.path.isabs(path) or ".." in path.split("/"):
            problems.append("entry point %r is not a safe relative path" % path)
            continue
        if not os.path.isfile(os.path.join(root, path)):
            problems.append("entry point file not found: %r" % path)

    for declared in entry_points.values():
        if str(declared) not in [entry_points.get(ENTRY_KEYS.get(k, ""), "") for k in manifest.get("kinds") or []]:
            problems.append("entryPoints.%s is declared but no kind uses it" % declared)

    for current, dirs, files in os.walk(root):
        if ".git" in dirs:
            dirs.remove(".git")
        for name in dirs + files:
            if os.path.islink(os.path.join(current, name)):
                problems.append("symlink in the plugin folder: %s"
                                % os.path.relpath(os.path.join(current, name), root))

    if problems:
        for problem in problems:
            print("FAIL: %s" % problem)
        return 1

    print("OK: %s %s (%s), entry points %s"
          % (manifest.get("name"), manifest.get("version"), plugin_id,
             ", ".join(sorted(str(v) for v in entry_points.values()))))
    return 0


if __name__ == "__main__":
    sys.exit(main())

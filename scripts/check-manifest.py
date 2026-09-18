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
import re
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


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def check_settings(root, manifest, problems):
    """The widget and the manifest must agree on the settings.

    A setting the QML reads but the manifest does not declare cannot be set from
    the bar's UI; one the manifest declares but nothing reads is a lie in the
    settings list. Where both sides carry a literal default they must match too,
    because the QML fallback is what a fresh install gets before anything is
    saved.
    """
    entry = manifest.get("entryPoints") or {}
    widget = str(entry.get("barWidget") or "")
    schema = [s for s in (manifest.get("barWidget") or {}).get("schema") or [] if isinstance(s, dict)]
    declared = {str(s["key"]): s for s in schema if s.get("key")}
    if not widget or not declared:
        return
    path = os.path.join(root, widget)
    if not os.path.isfile(path):
        return
    qml = read_text(path)

    used = set()
    fallbacks = {}
    for match in re.finditer(r'setting\(\s*"([A-Za-z0-9_]+)"\s*(?:,\s*([^)]+?))?\)', qml):
        key, literal = match.group(1), (match.group(2) or "").strip()
        used.add(key)
        if re.fullmatch(r'"[^"]*"|\'[^\']*\'|-?\d+(\.\d+)?|true|false', literal):
            fallbacks[key] = literal.strip('"\'')

    for key in sorted(used - set(declared)):
        problems.append("the widget reads setting %r but the manifest does not declare it" % key)
    for key in sorted(set(declared) - used):
        problems.append("the manifest declares setting %r but the widget never reads it" % key)
    for key, literal in sorted(fallbacks.items()):
        expected = declared.get(key, {}).get("defaultValue")
        if expected is None:
            continue
        # Lowercased: JSON true/false are Python True/False, and a naive compare
        # would report every boolean setting as a mismatch.
        if str(expected).strip().lower() != literal.strip().lower():
            problems.append("setting %r: manifest default %r but the widget falls back to %r"
                            % (key, str(expected), literal))


def check_markdown_tables(root, problems):
    """A row with the wrong number of cells silently breaks a table's layout.

    Pipes inside inline code are escaped (\\|), so they are not counted - that is
    the whole reason this check exists: an unescaped one turned a documented
    variable into a broken table.
    """
    cell_pipe = re.compile(r"(?<!\\)\|")
    for current, dirs, files in os.walk(root):
        if ".git" in dirs:
            dirs.remove(".git")
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            rel = os.path.relpath(os.path.join(current, name), root)
            block = []

            def flush():
                nonlocal block
                if len(block) >= 2:
                    counts = {count for _, count in block}
                    if len(counts) != 1:
                        problems.append("%s line %d: this table has rows with %s cells"
                                        % (rel, block[0][0], "/".join(str(c) for c in sorted(counts))))
                block = []

            for number, line in enumerate(read_text(os.path.join(current, name)).splitlines(), 1):
                if line.lstrip().startswith("|"):
                    block.append((number, len(cell_pipe.findall(line))))
                else:
                    flush()
            flush()


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

    check_settings(root, manifest, problems)
    check_markdown_tables(root, problems)

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

# Working on Hermbot

> Not called `AGENTS.md`, and not at the repository root, on purpose. Omarchy
> installs a plugin's whole tree into `~/.config/omarchy/plugins/`, so a root
> agent-instruction file would become ambient context for any coding agent the
> *installing user* happens to run - instructions they never chose to load.

Your Hermes Bot Mode roster in the Omarchy bar. A bot is a Hermes profile, and
this plugin reads the same files the desktop writes, so there is no second source
of truth to keep in sync and no token to configure.

**Which instance to follow is `lastUsed`, not `primary`.** Hermes Desktop
records the source the Sessions workspace last opened in `connections.json`
under `lastUsed` (its own comment: "the last source the Sessions workspace
successfully opened"); `primary` only moves when a connection is made primary,
and `launchMode: last-used` is about the *next* launch. Watching the file through
a switch shows `lastUsed` flipping while `primary` stands still. Do not use the
ssh tunnel as the signal either: the app's ControlMaster outlives a switch by
`ControlPersist` (measured: the forwarded port was still listening after the
window had gone back to this machine).

**Machine-independent by construction.** Nothing names a user, a home or an
install path. The three scripts find each other through their own location, and
`bin/hermbot_paths.py` resolves the four directories they need from the same
environment the rest of the system reads: `HERMES_HOME` (else `~/.hermes`),
`XDG_STATE_HOME` (else `~/.local/state`), `XDG_CONFIG_HOME` (else `~/.config`).
Two traps that cost real debugging: `HERMES_HOME` may be pinned to a *profile*
directory (that is what a profile-scoped process gets), so a value whose parent
is `profiles/` resolves up to the home; and a profile is only a bot when its
directory carries a marker Hermes writes, which is also what stops a machine
with no Hermes from answering with one phantom `default` bot. Copy the whole
`bin/` directory when installing by hand - the scripts import their sibling, and
a single file piped into `python3` cannot carry it (the ssh transport sends both
files as one bundle for exactly this reason).

**It only ever reads.** The roster, the avatars and the conversations come from
the Hermes Desktop install the widget is following - this machine, or the SSH
host the app is connected to (the watcher streams this same script there over one
ssh connection and re-emits its JSON lines; nothing is installed on the far side
and its own state is untouched, because the copy there writes scratch files under
`/tmp`). Nothing is written to a profile anywhere. What is written locally - this
machine - lives outside the plugin directory
(`~/.local/state/omarchy/hermbot/`) so an update cannot resurrect old events:
the notification state (`notify.json`), the outbox for a detached send
(`sends/`), the three bounded debug logs (`open.log`, `send.log`, `notify.log`),
and `seen.json` - the "you looked at it" watermark `hermbot-open` stamps and
`hermbot-watch` compares against each bot's own newest turn, plus, beside it, the
message-count baseline the unread badge counts from. If a change here would write
into a profile, it is the wrong change.

## Layout

| | |
| --- | --- |
| `bin/hermbot-watch` | follows the install and streams the roster as JSON lines |
| `bin/hermbot-open` | raises Hermes on a bot, down a ladder of ways in |
| `bin/hermbot-send` | says something to a bot, into its canonical Bot Chat |
| `Widget.qml` | the bar entry and the panel; **also where settings live** |
| `Avatar.qml` | one bot, drawn |
| `manifest.json` | the plugin id, kind and entry points Omarchy reads |
| `scripts/check-manifest.py` | the manifest contract, without Omarchy installed |

Settings only reach a bar widget, never a service, so everything configurable is
read in `Widget.qml` from the plugin's `shell.json` entry.

## The dev loop

The plugin folder *is* a git checkout, and **plugins are installed from committed
content only** - uncommitted QML installs as a broken widget, with no error to
tell you why. So the loop is commit first, every time:

```bash
git commit -am "..."                                   # 1. commit the change
omarchy plugin add file:///home/ozz1ee/Projects/hermbot   # 2. once, to install from the clone
omarchy plugin update <id> --yes                       # 3. after each further commit
omarchy restart shell                                  # 4. reload
```

Step 2 takes a `file://` URL, which is why the clone can be installed in place:
edit, commit, update, restart. Steps 3 and 4 are the ordinary loop after step 2
has been run once.

**Hot reload does not recreate `Variants` windows.** Editing `Widget.qml` or
`Avatar.qml` means a full `omarchy restart shell`, or you are looking at the old
surface and chasing a bug that is not there. Never `omarchy-refresh-shell`.

## Checking your work

```bash
python3 scripts/check-manifest.py .            # the manifest contract
qmllint Widget.qml Avatar.qml                  # CHECK THE EXIT CODE
bin/hermbot-watch --once --pretty           # one snapshot, human readable
omarchy plugin validate .                      # what the marketplace runs
```

`qmllint` is in Qt's own tools (`qt6-declarative-dev-tools` on Debian/Ubuntu, and
shipped with `qt6-declarative` here); on Ubuntu it lands in `/usr/lib/qt6/bin`.
CI installs it and puts that directory on `PATH`.

## CI pins its actions and asks for nothing

`.github/workflows/checks.yml` references third-party actions by full commit SHA,
never by a major tag: `@v5` can be repointed at different code, and that code
would then run in this repository's CI context. The workflow also declares the
minimum it needs - `permissions: contents: read` - so the default token keeps no
write access it does not use.

When bumping an action, **resolve the new SHA yourself from the tag** and keep
the `# vN` comment so a human can still see the version:

```bash
gh api repos/actions/checkout/git/ref/tags/v5 -q .object.sha
```

Never copy a SHA from another repository, this plugin's or anyone else's: a SHA
is only a pin for the project it came from, and a copied one is a pin for
something nobody checked.

## Things that cost a day to learn

**A canonical Bot Chat is hidden, and a hidden session has no door**

- `hermes://open/<session>?profile=<bot>` is delivered by Hermes Desktop and
  switches the window for a *visible* session - verified live, both directions.
  It does nothing for a canonical Bot Chat: those sessions are born hidden and
  the desktop's route validation only accepts a session id in its loaded
  (visible) list, so the navigation is dropped silently, with no error anywhere.
- The Bots roster is a plugin *pane*, not a route, so it has no address either.
  Until the app grows a door for bot chats (`hermes://bot/<name>`, or a
  `?bot=<name>` on a roster route), a click opens the bot's most recently active
  ordinary conversation - what the roster's own right-click does - and `--chat`
  is already implemented and correct for the day that door exists.

**Two watchers run, and a detached send outlives its launcher**

- Omarchy instantiates a bar widget twice (one copy measures), so two copies of
  `hermbot-watch` can be running. State is kept under `flock` in the state
  directory precisely because of that.
- The widget's `Process` is started once, when the shell starts, and Python
  loads the script then: after editing `bin/hermbot-watch` or
  `bin/hermbot-open`, `omarchy restart shell` is required or the bar keeps
  running the old code (it looks exactly like a broken feature).
- Measuring motion in the bar: widget IPC reports *logical* units and `grim`
  captures *physical* pixels, and this display is scaled 1.6x, so a crop taken
  from IPC geometry without multiplying by 1.6 measures wallpaper, reports "no
  animation anywhere", and sends you looking for code that was never wrong.
- A hover-free comparison needs the same yardstick on both sides: rapid frames
  (~300 ms apart) with the frame-to-frame changed-pixel count, run against both
  widgets in the same session. Idle bars are static in both (0 changed pixels),
  a greeting on panel open is ~23% of the cell in both, an arrival ~16%: the
  choreography is Rakabot's, it simply only runs when the state changes.
- `hermbot-send` hands the message over with
  `hermes -p <bot> chat --in ~ -c "Bot Chat" --create-if-missing -Q
  --query-file <file>`, so nothing is shell-interpreted and the canonical chat is
  created on demand by Hermes, never forked by this widget. A detached turn reads
  that file *after* the launcher has exited, so the file has to outlive the
  spawn: it lives at `0600` under the state dir and is pruned by the next run.
- Notifications only fire on transitions, and the first pass of a run records the
  world instead of describing it, so a bar that starts up does not replay what
  was already unread.

**This Hyprland is configured in Lua**

- Raising a window goes through the dispatcher, and on a Lua-configured Hyprland
  the dispatcher has to be called as Lua. `bin/hermbot-open --focus` is the
  file to read before touching anything in that path.

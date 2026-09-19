# Hermbot

Your **Hermes Bot Mode roster in the Omarchy bar**: every bot as its own avatar,
the newest thing it said, and one click to it.

![Hermbot in the bar and its panel](preview.png)

Both screenshots are the widget's own demo roster (`omarchy-shell ozz1ee.hermbot
demo`), so every part of it is visible at once - the bots, the session under
each one, the pinned section. Your own roster replaces them the moment the panel
opens.

A bot is a Hermes profile. There is no second source of truth here: the widget
reads the same files the desktop writes (`profile.yaml`'s `ui_meta['hermes-bots']`
for the avatar, each profile's session store for the canonical **Bot Chat**), so
a bot created, renamed or recoloured in Hermes Desktop shows up in the bar
without any configuration on this side.

The bar entry, on its own:

![The bots that want you beside the mark](assets/bar.png)

The faces are the bots that want you: unread in Hermes Desktop, or working right
now. When none of them does, the mark stands alone.

Built and running on a live install: bar faces in each bot's own shape and
colour, the "waiting on you" count in the panel, notification cards on a bot
write, and a click - from the bar or from any row - that opens that bot. The
drawing engine is Rakabot's, adapted - see `NOTICE` for the lineage.

## What it does

| | today |
|---|---|
| Roster in the bar: the bots that want you, drawn as themselves | yes (a number instead with `barMetric: count`, or the mark alone with `none`) |
| Panel: sections, newest preview, relative time, activity | yes |
| Under each bot: the session it is in, else the last one it finished | yes, and clicking it opens that session |
| Pinned chats, grouped by the bot they belong to | yes (`p` hides the section, the choice is saved) |
| Follow Hermes Desktop to another host (SSH connection) | yes (`s` toggles auto/local; the header names the instance) |
| Desktop notification when a bot writes, click opens that bot | yes |
| Send a message into a bot's canonical Bot Chat | via `bin/hermbot-send` (the panel has no input, as in Rakabot) |
| Open Hermes on the bot's most recent conversation | yes |
| Open Hermes directly on the bot's **canonical Bot Chat** | waiting on upstream: PR [#115195](https://github.com/NousResearch/hermes-agent/pull/115195) adds `hermes://bot/<profile>`, verified live from this widget's side - until it ships, a click opens the bot's most recently active visible session |

## Keys, mouse and IPC

With the panel open (click the mark, or `omarchy-shell ozz1ee.hermbot toggle`):

| key | does |
|---|---|
| `j` / `k` | move down / up through the rows (bots, the session under each, pinned chats) |
| `Enter` | open the row under the cursor |
| `g` | cycle the panel order (`attention` -> `gateway` -> `flat`), saved |
| `p` | show or hide the PINNED section, saved |
| `s` | follow the app (`auto`) or this machine (`local`), saved |
| `r` | cycle what the bar draws beside the mark (`avatars` -> `count` -> `none`), saved |
| `h` | hide the panel |

On the bar entry: left click opens the panel, middle click cycles the bar metric,
right click opens the bot at the top of the roster - the one that wants you most.
The footer of the panel spells the keys out, shortening as the panel narrows.

Everything the panel does can be driven without a keyboard, which is how it is
tested and how the screenshots above were taken:

| command | does |
|---|---|
| `omarchy-shell ozz1ee.hermbot state` | counts, gateway state, how many faces are in the bar |
| `omarchy-shell ozz1ee.hermbot toggle` / `open` / `close` | the panel |
| `omarchy-shell ozz1ee.hermbot demo` | switch to the demo roster and back |
| `omarchy-shell ozz1ee.hermbot metric` / `group` / `pinned` | the same cycles as `r`, `g`, `p` |
| `omarchy-shell ozz1ee.hermbot order flat` | set the order outright (`attention`, `gateway`, `flat`) |
| `omarchy-shell ozz1ee.hermbot geometry` | the panel's rectangle in logical pixels, for a screenshot crop |
| `omarchy-shell ozz1ee.hermbot look 120 340` / `away` | aim the avatars' eyes at a point, e.g. while recording |

## Settings

Six settings, all in the bar's own settings UI (`omarchy bar`). Every one a key
cycles is written back through `omarchy bar set`, so the choice survives a
restart and a plugin update.

| key | default | what it does |
|---|---|---|
| `barMetric` | `avatars` | what sits beside the mark: `avatars` = the bots that want you, up to `maxBarAvatars`, drawn as themselves; `count` = one number, how many want you; `none` = the mark alone. Avatars mode deliberately shows no number - the faces carry it |
| `maxBarAvatars` | `3` | how many faces beside the mark, at most (1-6) |
| `ordering` | `attention` | panel order: `attention` puts the bots that want you first, longest wait at the top, then a rule and everyone else by recency; `gateway` groups by what the gateway serves and what it does not; `flat` is pure recency |
| `showPinned` | `true` | the PINNED section, grouped by the bot each chat belongs to |
| `source` | `auto` | which instance to read: `auto` follows Hermes Desktop's own connection, `local` always reads this machine |
| `notifyOnMessage` | `true` | an Omarchy card when a bot writes, with a click that opens that bot - transitions only, at most one card per bot |

## Requirements

- Omarchy (Quattro) with the bar, `omarchy-notification-send` on `PATH`
- A Hermes install (`HERMES_HOME`, else `~/.hermes`), gateway or desktop backend running
- `python3` (standard library only - no pip installs, no venv)

## Install

```bash
omarchy plugin add https://github.com/ozz1ee-dev/omarchy-hermbot --enable
omarchy bar put ozz1ee.hermbot --section center
```

Nothing is compiled and nothing is installed system-wide: the plugin is a folder
of QML and Python that Omarchy clones into `~/.config/omarchy/plugins/`, and
`omarchy plugin update ozz1ee.hermbot` is how it is updated later. The second
line puts it on the bar; after that, its settings live in the bar's own settings
UI.

## Uninstall

```bash
omarchy plugin remove ozz1ee.hermbot --yes
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/hermbot"
```

The first line takes the widget off the bar and deletes the plugin folder. The
second drops this plugin's own state - the notification record and the "you
looked at it" watermark - which nothing else reads. Neither line touches a
Hermes profile, and no Hermes install is modified.

## On someone else's machine

Nothing here names a user, a home directory or an install path: the scripts find
each other through their own location, and every directory they read follows the
same environment the rest of the system uses.

| what | where it comes from |
|---|---|
| the Hermes install | `HERMES_HOME`, else `~/.hermes` (when the variable is pinned to a single profile directory, which is what a profile-scoped process gets, it resolves up to the home) |
| this plugin's own state | `${XDG_STATE_HOME:-~/.local/state}/omarchy/hermbot` |
| Hermes Desktop's registry | `${XDG_CONFIG_HOME:-~/.config}/Hermes`, whichever copy actually holds a registry |
| the packaged desktop binary | `HERMES_HOME/hermes-agent/apps/desktop/release`, overridable with `HERMBOT_DESKTOP_BIN` |
| the roster | whatever instance the app is connected to (see the binaries below) |

A profile counts as a bot only when its directory carries something Hermes writes
(`config.yaml`, `profile.yaml`, `auth.json`, `state.db`, ...) - never a directory
of sessions or logs - and a machine with no Hermes at all says so instead of
inventing a bot. `python3 scripts/check-portability.py` builds such a foreign
world in a temporary directory and checks all of it; CI runs the same script on a
runner that has neither Omarchy nor Hermes installed.

## The three binaries

All reads are read-only, from the instance Hermes Desktop is on; nothing is
written to a profile and no credential is ever needed. There is no token to
configure - unlike a hosted chat service, the Hermes roster is already on disk.
When the desktop is pointed at an SSH host, that host's roster is read the same
way: the watcher runs this same script there over one ssh connection it holds
open, and the only thing written on the far side is a scratch directory under
`/tmp` that the copy there uses for its own state. Set `source` to `local` (or
press `s`) to pin the bar to this machine regardless.

The three scripts also answer to environment variables, for the cases where a
flag cannot be passed (the widget starts the watcher itself):

| variable | does |
|---|---|
| `HERMBOT_ROOT` | the Hermes home to read, the same as `--hermes-root` |
| `HERMBOT_SOURCE` | the default source: `auto`, `local`, or `ssh:<id\|host>` |
| `HERMBOT_DESKTOP_BIN` | an executable to hand `hermes://` links to instead of the packaged app (a build from a branch, or a dev instance on its own profile) |
| `HERMBOT_OPEN` | the opener to call instead of the sibling `hermbot-open` |
| `HERMBOT_SEND_FILE` | the query file a detached send reads - set by `hermbot-send` itself |

### `bin/hermbot-watch`

Follows the install and streams the roster as JSON lines.

```bash
hermbot-watch [--once] [--pretty] [--notify] [--interval SECONDS]
              [--source auto|local|ssh:<id|host>] [--hermes-root DIR]
              [--appdata DIR] [--state FILE] [--seen FILE] [--mark-seen NAME]
```

```bash
hermbot-watch --once --pretty      # one snapshot, human readable
hermbot-watch --interval 2        # stream (what the widget runs)
hermbot-watch --interval 2 --notify   # ... and raise cards on bot writes
hermbot-watch --mark-seen dev     # record that dev was opened (hermbot-open calls this)
```

`--once` is a read-only query: it never writes the `seen` watermark. The
streaming watcher does seed bots it has no record for (at their own last turn),
so a fresh install announces nothing.

The rest of the options exist for the cases where the defaults are wrong:
`--source` overrides what the widget follows (the same value the `source`
setting carries, `ssh:` included), `--hermes-root` reads an install somewhere
else, `--appdata` points at another Hermes Desktop state directory, `--state` and
`--seen` move the two state files (that is how a remote stream keeps its own),
and `--mark-seen` stamps the watermark by hand.

The snapshot is the widget's whole data source:

```json
{
 "counts": {"bots": 3, "waiting": 1, "active": 1, "no_chat": 0, "pinned": 6},
 "gateway": {"pid": 3748184, "running": true, "profiles": ["default", "dev", "web"]},
 "bots": [{
  "name": "dev", "handle": "@dev", "title": "Dev - Local",
  "shape": "blobatar::round", "color": "#dd4b66",
  "chat": {"session_id": "20260905_131013_938fbf", "exists": true, "hidden": true,
       "unread": false, "message_count": 200, "preview": "...",
       "preview_role": "assistant", "from_bot": null},
  "recent_session": {"session_id": "20260918_145557_e98322", "title": "..."},
  "active": true, "waiting": true, "unread_count": 3,
  "desktop_unread": true, "wrote_at": 1789748368.0, "seen_at": 1789751582.0,
  "open": {"deep_link": "hermes://open/<bot-chat>?profile=dev",
       "recent_deep_link": "hermes://open/<recent>?profile=dev"}
 }]
}
```

Definitions are taken from the desktop's own code, not invented:

- **waiting on you** = the bot's own chat is unread according to Hermes Desktop.
  The app tracks that in its own store rather than in the session database:
  `sessions.last_read_at` is written only when a row is explicitly toggled, so on
  a normal install it is NULL for every session and every bot would read as read.
  What the app actually draws a green dot from is
  `hermes.desktop.unreadFinishedSessions` (Electron's localStorage, bucketed per
  profile and keyed by the durable session id - the same id this widget resolves
  as the bot's canonical chat), so that is the record the widget reads. A chat
  read in the app window clears here too. Where the app keeps no record at all - a
  machine that never ran it - the widget falls back to its own watermark: the
  bot's own newest turn is newer than the last time that bot was opened from the
  bar (`~/.local/state/omarchy/hermbot/seen.json`, stamped by `hermbot-open`).
  It is seeded at the bot's own last turn, so a fresh install announces nothing.
  The two are never mixed on one record: beside a live desktop record the fallback
  would leave a bot marked forever after a chat read in the app window.
- **the badge** = how many messages are waiting in that bot's chat, drawn as a
  count the way Rakabot draws one. The app's own message-count watermark is not
  readable - it lands in a compressed LevelDB block and its session ids come back
  truncated - so the number is the widget's own: the chat's `message_count` minus
  a baseline kept beside the click record, seeded at first sight and re-stamped on
  every poll where the chat is not waiting. `max(1, message_count - baseline)`. A
  bot that is already waiting the first time the widget sees it reads `1`: its
  real backlog predates any baseline the widget holds, and a larger number would
  be invented.
- **active** = a message in any of the bot's sessions within 90 s (the roster's
  own activity window).
- **the session under a bot** = the one it is still in (`ended_at` is NULL), and
  when it is in none, the last one it finished - newest by activity either way,
  because several sessions can be left open at once. Hidden sessions are skipped:
  the row exists to be opened, and a canonical Bot Chat is not openable. The
  marker says which of the two you are looking at, and the accent colour means
  the bot is in it right now.
- **pinned** = `pinned = 1` on a visible session, listed in its own section under
  the bot it belongs to - the desktop's own Pinned, and never a second copy of a
  row that is already in the list.
- **row order** = newest of (bot created, newest message in any of its sessions).
- **canonical chat** = the session titled exactly `Bot Chat` - always hidden, and
 the only door to a bot's forever-conversation.

Notifications only fire on **transitions**, only when the **bot** wrote (being
told about a message you just sent is noise), at most one card per bot (replace
id), and the first run records the world instead of describing it. State lives
outside the plugin directory (`~/.local/state/omarchy/hermbot/`) under
`flock`, because a bar widget is often instantiated twice and both copies run a
watcher. Failures are logged to `notify.log`, never swallowed.

### `bin/hermbot-open`

Raises Hermes on a bot.

```bash
hermbot-open --bot NAME [--chat | --session ID] [--focus] [--print] [--json]
```

`--chat` targets the canonical Bot Chat instead of the bot's most recent visible
session (correct, but the desktop drops that link today - see the upstream gap
below). `--session` opens one exact session id, which is what a session row in
the panel clicks. `--print` reports what it would do, `--json` makes that
machine-readable, `--source` and `--hermes-root` resolve the bot on the same
instance the bar is showing.

Ladder, in order: launch the packaged Electron binary with
`hermes://open/<session>?profile=<bot>` as argv (the running app picks it up
through its single-instance handler; a cold app boots on it) -> `xdg-open` the
link -> raise the window only. `--focus` also raises the window through Hyprland
(note: this Hyprland is Lua-configured, so the dispatcher must be called as Lua).

### `bin/hermbot-send`

Says something to a bot, into its canonical Bot Chat - the same conversation the
desktop, the CLI and the bot-to-bot `message_agent` tool use.

```bash
hermbot-send --bot NAME [--text TEXT] [--wait] [--print] [--json]
```

```bash
hermbot-send --bot dev "status?"    # detached: the reply arrives as a card
echo "long text" | hermbot-send --bot web
hermbot-send --bot dev --wait "ping"  # foreground, prints the reply
```

Text comes from `--text` or stdin. `--wait` runs it in the foreground and prints
the reply instead of letting the answer come back as a notification card;
`--print` shows the command it would run and `--json` the result.

The delivery door is the one Hermes itself uses for bot-to-bot DMs:
`hermes -p <bot> chat --in ~ -c "Bot Chat" --create-if-missing -Q --query-file <file>`,
so nothing is shell-interpreted and the canonical chat is created on demand by
Hermes, never forked by this widget. The message file must outlive the spawn (a
detached turn reads it after the launcher exits), so it lives under the state
dir at `0600` and is pruned by the next run.

## The upstream gap: opening a bot's own chat

`hermes://open/<session-id>?profile=<bot>` is delivered by Hermes Desktop and
switches the window for a **visible** session - verified live, both directions.
It does **not** work for a canonical Bot Chat: those sessions are born hidden, and
the desktop's route validation only accepts a session id that is in its loaded
(visible) list, so the navigation is dropped silently. The Bots roster is a
plugin *pane*, not a route, so it has no address either.

Until the app grows a door for bot chats (`hermes://bot/<name>`, or a
`?bot=<name>` on a roster route), this widget opens the bot's most recently
active ordinary conversation - exactly what the roster's own right-click does - 
and `--chat` is already implemented and correct for the day the door exists.
A pull request implementing `hermes://bot/<profile>` was opened against the app
from this report ([#115195](https://github.com/NousResearch/hermes-agent/pull/115195))
and is still open; it has since drifted from the app's main branch, so no arrival
date can be promised, and the live test of it was run against a build of that
branch rather than a release.

## Roadmap

1. A **remote-gateway** connection (URL + token, no ssh) is not read yet: the
   app's choice is visible in `connections.json`, but its stored token is rotated
   on every gateway restart and the roster would have to be mapped from that
   API's shapes. Until then the bar keeps reading this machine, and the panel
   header says so (`local only`) rather than pretending to show the remote. An
   SSH connection - the one this was built and measured against - is fully
   supported.
2. Flip the click to the **canonical Bot Chat** the day `hermes://bot/<profile>`
   ships in a released desktop (`HERMBOT_DESKTOP_BIN` already lets the door be
   tested against a build from a branch).
3. Marketplace submission.

## Development

The plugin folder is a git checkout, so the dev loop is commit-first:

```bash
git commit -am "..." && omarchy plugin update <id> --yes && omarchy restart shell
```

Plugins are installed from committed content only; uncommitted QML installs as a
broken widget with no error.

Four checks run on every push (`manifest`, `qml`, `portability`, `ascii`). The
last but one is the interesting one: it builds a foreign machine in a temporary
directory - its own `HERMES_HOME`, its own `XDG_*` directories, its own bot
names, and the negative cases - and runs the watcher inside it, so an assumption
about the author's machine fails in CI instead of on a stranger's laptop.

```bash
python3 scripts/check-portability.py     # what CI runs on ubuntu-latest
python3 scripts/check-manifest.py .      # the manifest contract
python3 scripts/check-portability.py && python3 scripts/check-manifest.py .
```

To look at the widget without touching your own roster, `omarchy-shell
ozz1ee.hermbot demo` switches both the bar and the panel to the demo bots, and
the same command switches back. Release history is in `CHANGELOG.md`.

## License

Apache-2.0. `Widget.qml` and `Avatar.qml` are derived from **Rakabot** (my own
plugin for Rakazo, Apache-2.0), which is itself a QML derivative of
[njpatel/omabot](https://github.com/njpatel/omabot) - the visual design, the
avatar rendering and the bar/panel layout come from that lineage. `NOTICE` names
both, and each derived file carries a notice of modification at the top. The
data layer, the actions and the documentation are new here.

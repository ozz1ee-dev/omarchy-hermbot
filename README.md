# Hermesbots

Your **Hermes Bot Mode roster in the Omarchy bar**: every bot as its own avatar,
the newest thing it said, and one click to it — plus typing to a bot straight
from the panel.

A bot is a Hermes profile. There is no second source of truth here: the widget
reads the same files the desktop writes (`profile.yaml`'s `ui_meta['hermes-bots']`
for the avatar, each profile's session store for the canonical **Bot Chat**), so
a bot created, renamed or recoloured in Hermes Desktop shows up in the bar
without any configuration on this side.

Status: the headless core is built and verified against a live Hermes install
(three bots, notification cards, a real message delivered into a Bot Chat). The
QML bar widget is the remaining piece — see **Roadmap**.

## What it does

| | today |
|---|---|
| Roster in the bar: avatar per bot, "waiting on you" count | yes |
| Panel: sections, newest preview, relative time, activity | yes |
| Desktop notification when a bot writes, click opens that bot | yes |
| Send a message into a bot's canonical Bot Chat from the panel | yes |
| Open Hermes on the bot's most recent conversation | yes |
| Open Hermes directly on the bot's **canonical Bot Chat** | not yet — upstream gap, see below |

## Requirements

- Omarchy (Quattro) with the bar, `omarchy-notification-send` on `PATH`
- A local Hermes install (`~/.hermes`), gateway or desktop backend running
- `python3` (standard library only — no pip installs, no venv)

## The three binaries

All reads are read-only, from the local install; nothing is written to a profile
and nothing is sent off the machine. There is no token to configure — unlike a
hosted chat service, the Hermes roster is already on disk.

### `bin/hermesbots-watch`

Follows the install and streams the roster as JSON lines.

```bash
hermesbots-watch --once --pretty            # one snapshot, human readable
hermesbots-watch --interval 5               # stream (what the widget runs)
hermesbots-watch --interval 5 --notify      # ... and raise cards on bot writes
```

The snapshot is the widget's whole data source:

```json
{
  "counts": {"bots": 3, "waiting": 0, "active": 1, "no_chat": 0},
  "gateway": {"pid": 3748184, "running": true, "profiles": ["default", "dev", "web"]},
  "bots": [{
    "name": "dev", "handle": "@dev", "title": "Dev - Local",
    "shape": "blobatar::round", "color": "#dd4b66",
    "chat": {"session_id": "20260905_131013_938fbf", "exists": true, "hidden": true,
             "unread": false, "message_count": 200, "preview": "...",
             "preview_role": "assistant", "from_bot": null},
    "recent_session": {"session_id": "20260918_145557_e98322", "title": "..."},
    "active": true, "waiting": false,
    "open": {"deep_link": "hermes://open/<bot-chat>?profile=dev",
             "recent_deep_link": "hermes://open/<recent>?profile=dev"}
  }]
}
```

Definitions are taken from the desktop's own code, not invented:

- **waiting on you** = the backend watermark: `last_read_at` NULL means *read*,
  `0` means *unread*, otherwise unread when activity postdates it
  (`SessionDB.session_unread`). Verified A/B against that function: identical on
  all six watermark cases, including both edge values.
- **active** = a message in any of the bot's sessions within 90 s (the roster's
  own activity window).
- **row order** = newest of (bot created, newest message in any of its sessions).
- **canonical chat** = the session titled exactly `Bot Chat` — always hidden, and
  the only door to a bot's forever-conversation.

Notifications only fire on **transitions**, only when the **bot** wrote (being
told about a message you just sent is noise), at most one card per bot (replace
id), and the first run records the world instead of describing it. State lives
outside the plugin directory (`~/.local/state/omarchy/hermesbots/`) under
`flock`, because a bar widget is often instantiated twice and both copies run a
watcher. Failures are logged to `notify.log`, never swallowed.

### `bin/hermesbots-open`

Raises Hermes on a bot.

```bash
hermesbots-open --bot dev [--focus] [--print]
```

Ladder, in order: launch the packaged Electron binary with
`hermes://open/<session>?profile=<bot>` as argv (the running app picks it up
through its single-instance handler; a cold app boots on it) → `xdg-open` the
link → raise the window only. `--focus` also raises the window through Hyprland
(note: this Hyprland is Lua-configured, so the dispatcher must be called as Lua).

### `bin/hermesbots-send`

Says something to a bot, into its canonical Bot Chat — the same conversation the
desktop, the CLI and the bot-to-bot `message_agent` tool use.

```bash
hermesbots-send --bot dev "status?"        # detached: the reply arrives as a card
echo "long text" | hermesbots-send --bot web
hermesbots-send --bot dev --wait "ping"    # foreground, prints the reply
```

The delivery door is the one Hermes itself uses for bot-to-bot DMs:
`hermes -p <bot> chat --in ~ -c "Bot Chat" --create-if-missing -Q --query-file <file>`,
so nothing is shell-interpreted and the canonical chat is created on demand by
Hermes, never forked by this widget. The message file must outlive the spawn (a
detached turn reads it after the launcher exits), so it lives under the state
dir at `0600` and is pruned by the next run.

## The upstream gap: opening a bot's own chat

`hermes://open/<session-id>?profile=<bot>` is delivered by Hermes Desktop and
switches the window for a **visible** session — verified live, both directions.
It does **not** work for a canonical Bot Chat: those sessions are born hidden, and
the desktop's route validation only accepts a session id that is in its loaded
(visible) list, so the navigation is dropped silently. The Bots roster is a
plugin *pane*, not a route, so it has no address either.

Until the app grows a door for bot chats (`hermes://bot/<name>`, or a
`?bot=<name>` on a roster route), this widget opens the bot's most recently
active ordinary conversation — exactly what the roster's own right-click does —
and `--chat` is already implemented and correct for the day the door exists.

## Roadmap

1. `Widget.qml` — bar avatars (shape + colour from `ui_meta`), panel with
   sections, preview, unread, an input that calls `hermesbots-send`, click that
   calls `hermesbots-open`.
2. `assets/hermesbots.png` — our own card icon (until then the card uses the
   `hermes` icon from the desktop's install).
3. Manifest, CI, marketplace submission.

## Development

The plugin folder is a git checkout, so the dev loop is commit-first:

```bash
git commit -am "..." && omarchy plugin update <id> --yes && omarchy restart shell
```

Plugins are installed from committed content only; uncommitted QML installs as a
broken widget with no error.

## License

MIT. No visuals are borrowed from another plugin yet; if any are, the licence
follows the visuals and a `NOTICE` will name the origin.

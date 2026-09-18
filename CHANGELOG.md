# Changelog

## 0.3.0

- The bar follows Hermes Desktop: switch the app to another host and the roster
  becomes that host's bots (within a poll), with the panel header naming the
  instance. An SSH connection is read by streaming this same watcher script to
  the other machine over one long-lived ssh connection, so nothing has to be
  installed there and no token has to be minted; the copy there keeps its own
  state in `/tmp`, and notifications, the "you looked at it" watermark and the
  session links stay decided on this side. The `s` key (or the `source` setting)
  pins the bar to this machine when you would rather not follow.
- A click resolves against the followed instance, and a bot is found by profile
  name, display title or `@handle` - a single-profile install calls itself
  `default` while showing "Hermes - Ovhlab" and answering to `@hermes`.

## 0.2.0

- Each bot now carries the session it is in - or, when it is in none, the last one
  it finished - and a click on that row opens it. The section under the bot list is
  Hermes Desktop's own Pinned, grouped by the bot each chat belongs to, with every
  row openable through the same session deep link; `p` hides it and the choice is
  saved.
- Opening a session from those rows deliberately does **not** clear the bot's
  "it wrote and you have not looked" watermark: a pinned chat is a different
  conversation, and reading it is not reading what the bot said to you.

## 0.1.0

- First release: your Hermes Bot Mode roster in the Omarchy bar. A bot is a
  Hermes profile, and the widget reads the same files the desktop writes - the
  avatar from `profile.yaml`'s `ui_meta['hermes-bots']`, the conversation from
  each profile's session store - so a bot created, renamed or recoloured in
  Hermes Desktop shows up without any configuration here. There is no second
  source of truth and no token to mint: unlike a hosted chat service, the roster
  is already on disk.
- The bar: one avatar per bot, drawn in the shape and colour Hermes gives it,
  with the "waiting on you" count. The panel: sections, the newest thing a bot
  said, relative time, and activity.
- Waiting, working and active states. "Active" is the desktop's definition: a
  message in any of the bot's sessions within 90 seconds. "Waiting on you" is
  two rules: the backend watermark (`SessionDB.session_unread`, verified A/B
  against the desktop's function on all six watermark cases, both edge values
  included) OR the widget's own - the bot's newest turn is newer than the last
  time you opened it from the bar (`seen.json`, stamped by `hermbot-open`).
  The second rule is what keeps the roster alive in production: the desktop
  never writes its watermark while you simply read, and the avatars only
  animate on state changes, so without it a bar would show one idle face while
  Rakabot-era screenshots showed a bouncing crowd.
- Desktop notification when a bot writes, and clicking it opens (or switches to)
  that bot. Only transitions are announced - starting the bar does not replay
  what was already unread - only when the *bot* wrote, one card per bot, and the
  first pass of a run records the world instead of describing it. Two watchers
  run (Omarchy instantiates a bar widget twice) and announce an event once.
- Send a message into a bot's canonical **Bot Chat** with `bin/hermbot-send`,
  through the same door Hermes itself uses for bot-to-bot DMs: the canonical chat
  is created on demand by Hermes, never forked by this widget, and nothing is
  shell-interpreted. The panel deliberately has no input, exactly as Rakabot's
  does not.
- `bin/hermbot-watch` follows the install and streams the roster as JSON
  lines; `bin/hermbot-open` raises Hermes on a bot (packaged binary with the
  deep link as argv, then `xdg-open`, then raise the window); `bin/hermbot-send`
  says something to a bot, detached with the reply arriving as a card, or in the
  foreground.
- Read-only by construction. Every read is from the local install, nothing is
  written to a profile, and nothing leaves the machine. The one thing written
  locally is notification state, kept outside the plugin directory so an update
  cannot resurrect old events.
- Known gap: opening Hermes directly on a bot's canonical Bot Chat does not work
  yet. Those sessions are born hidden and the desktop's route validation only
  accepts a session id in its loaded (visible) list, so
  `hermes://open/<session>?profile=<bot>` is dropped silently. Until the app
  grows a door for bot chats, a click opens the bot's most recently active
  ordinary conversation - what the roster's own right-click does - and `--chat`
  is already implemented for the day that door exists.

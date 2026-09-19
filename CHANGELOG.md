# Changelog

## 0.4.2

- **Fixed a badge that could never be cleared, reported from real use.** A bot showed
  a count that survived every click: the number was measured against the bot's
  canonical `Bot Chat` while the click opened its most recently active *visible*
  session - two different conversations, so reading one never cleared the other. The
  canonical chat is hidden and the desktop refuses a deep link into a session that is
  not in its loaded list (verified live: a link straight into that chat left its
  marker in place), so the count sat on a conversation the bar has no door to. The
  badge is now read from the newest visible session - the same row the click opens.
- **The baseline is the desktop's own count whenever it has one.** It was assumed
  unreadable (the record sometimes lands in a compressed LevelDB block), but when a
  compaction leaves it in a plain one it reads fine, and it is authoritative: the app
  stamps it every time it shows a chat. It now takes precedence, and the widget's own
  baseline is the fallback for a machine that never ran the app. Without this a bot
  whose chat had moved on showed a count of 29 where one message had arrived.
- **The widget's own baseline is keyed by session id as well as bot.** It was stored
  per bot, so when the row a click reaches changed, a count from the previous
  conversation was subtracted from a different one - a nonsense badge (587 where one
  message had arrived). An older record without an id is read as no baseline.
- **Nothing on disk can take the watcher down any more.** Every number read from the
  state file went through a bare `float()`/`int()`, so a truncated, hand-edited or
  older-format `seen.json` raised and killed the watcher - and with it the widget. One
  pair of helpers now degrades an unreadable value to "no stamp" / zero instead. Proven
  by injecting a corrupted state file into a running widget: it survived with no error.

## 0.4.1

- **Fixed a security review finding: nothing of ours is addressed by a fixed path
  on a machine we do not own.** The ssh source unpacked its bundle into
  `/tmp/hermbot-watch-<uid>` - a name any other account on a shared host can create
  first, as a directory it owns or as a symlink pointing anywhere - after removing
  and recreating that path. It now creates a directory for the connection and
  verifies what it got: the session's own `XDG_RUNTIME_DIR` when there is one
  (private to the account, cleared with the session), else a randomly named
  `mkdtemp` directory, checked to be a real directory the account owns and forced
  to `0700` before anything is unpacked into it. The remote watcher's state files
  now live inside that directory instead of at fixed `/tmp` names, and only a
  directory that passed the check is ever pruned - of runs old enough to be
  nobody's live connection.
- **Every write now refuses to follow a symlink and never writes through a
  pre-made entry.** The state files, the click watermark and the log trims all went
  through fixed `.tmp` names written with `write_text`, and the lock file was opened
  with `open("w")` - a truncating open at a predictable name, which a link planted
  in a writable directory turns into destroying whatever it points at. One helper
  now creates the temporary with `O_EXCL`, refuses anything at that name that is not
  a regular file the account owns, and swaps it in with a rename; the lock opens
  `O_RDWR|O_CREAT` without `O_TRUNC` and without following links; the log append and
  the message file `hermbot-send` hands to the detached child are opened the same
  way, the latter through the descriptor `mkstemp` returned rather than by reopening
  the name.
- `send.out`, the detached child's output file, is bounded like the other logs -
  nothing was pruning it either.

## 0.4.0

- **Bots can finally be seen waiting on you.** The roster used to sit flat because
  it read the backend's read watermark (`sessions.last_read_at`), which nothing
  stamps on a plain read - on a normal install it is NULL for every session, so
  every bot read as read. Hermes Desktop tracks the same thing in its own store,
  and the watcher now reads that record: the app's `unreadFinishedSessions`
  markers, keyed by the durable session id and bucketed per profile, which is
  exactly the canonical chat the widget already resolves. A chat the app shows
  unread now wears the excited face and a badge. The app's store stays the
  authority - a chat read in its window clears here too, which a click-only
  watermark never did.
- **The unread badge shows a count, not a dot.** Rakabot draws a number there and
  this widget drew a bullet; it now carries the number of messages waiting in that
  bot's chat. The desktop's own message-count watermark is not readable (it lands
  in a Snappy-compressed LevelDB block, so its session ids come back truncated),
  so the count is the widget's own: a per-bot baseline kept beside the click
  record, seeded at first sight and re-stamped on every poll where the chat is not
  waiting. `max(1, message_count - baseline)`. A bot that is already waiting the
  first time the widget sees it reads `1` - its real backlog predates any baseline
  we hold, and a larger number would be invented.
- **The bot name no longer takes the urgent colour.** Rakabot's own name line is
  `focused ? accent : fg`, and its `focused` is a dead field - both writers set it
  to False and nothing ever raises it - so its names are always the foreground.
  This widget tinted a waiting bot's name `urgent`, which is what made the two
  rosters look different despite identical type. Measured, not eyeballed: the same
  name renders 13x90 px at the same coordinates in both panels, so the type was
  already 1:1 and only the colour was not. Weight and the badge still carry "this
  one wants you".
- **Removed the freshness window (`freshAfterS`).** It existed to keep the roster
  from sitting flat while the host's unread was unreachable, and it was a
  deviation - Rakabot has no such window, and it altered 0 bots' faces once the
  waiting branch came first. The host's own 90-second `active` window is the one
  deliberate addition that stays.
- The widget's own click watermark is now a fallback, used only where the desktop
  keeps no record at all (a machine that never ran the app). Beside a live desktop
  record it left a bot marked forever after a chat read in the app window.
- The three state logs (`open.log`, `send.log`, `notify.log`) are bounded: each
  keeps its last 128 KB once it passes 256 KB. They were append-only, on files
  nothing prunes.
- The ssh source closes its child's pipes before each reconnect instead of leaving
  the descriptors to the interpreter's collector.

## 0.3.7

- The same hole, one line further down: the pinned-agent header read `.title`
  off a `bot` that section, rule and pinned-header rows do not have, so the
  `TypeError` kept arriving from that binding after 0.3.6 fixed the session
  line beside it. It now reads the bot defensively too. Both lines in the
  delegate that touch a field only some row kinds own are guarded, and the
  whole delegate was swept for the same shape (a bare `modelData.<field>.<sub>`
  outside a ternary or `&&` chain is the only way to hit it).

## 0.3.6

- Fixed a `TypeError` thrown on every list rebuild: the session line's `text`
  binding ran for every row, including the bot rows that carry no `session`
  object, and read `.title` off `undefined`. QML evaluates a binding even when
  the item is invisible, so the error arrived in bursts while the widget ran
  (six per rebuild - three bots on two screens) and that row's text was lost
  with it. The binding now answers only for the row kinds that own a session,
  and reads it defensively, the way the timestamp line beside it already did.

## 0.3.5

- The README now carries install and removal instructions (`omarchy plugin add`
  / `omarchy plugin remove` plus the state directory to drop), which is a
  marketplace checklist item. Documentation only.

## 0.3.4

- NOTICE records the upstream author's public confirmation that reuse of omabot
  under Apache-2.0 is welcome with the licence and notice requirements preserved
  (njpatel/omabot#5). No code changed.

## 0.3.3

Documentation and screenshots only; no behaviour changed.

- The settings table claimed avatars mode draws a "waiting on you" count beside
  the faces. It does not, by design: that number belongs to `barMetric: count`,
  and in avatars mode the faces are the signal. The README, the manifest
  description and the bar caption now say what the code does.
- Documented what until now could only be found by reading the source: the panel
  keys and all three mouse buttons, the IPC commands (`state`, `toggle`, `demo`,
  `geometry`, `order`, `look`, ...), every setting with its default and real
  effect, the full option list of all three binaries, and the five environment
  variables they answer to.
- Both screenshots retaken on an empty workspace with the neighbouring Rakazo
  widget hidden, from the widget's own demo roster, now with the `s` key in the
  footer.
- The upstream section states the pull request's real state: open, drifted from
  the app's main branch, and tested against a build of that branch rather than a
  release.

## 0.3.2

- The plugin no longer assumes this machine. `HERMES_HOME`, `XDG_STATE_HOME` and
  `XDG_CONFIG_HOME` are respected, each falling back to the stock path, so a
  moved install, a relocated state directory and a desktop whose registry lives
  outside `~/.config` are read correctly. `HERMES_HOME` pinned to a single
  profile directory - what a profile-scoped process gets - resolves up to the
  home instead of reading that one profile as the default bot.
- A machine with no Hermes at all now says `no Hermes install here` instead of
  answering with one phantom `default` bot: the marker rule the named profiles
  already had now applies to the home too.
- The ssh transport sends the whole `bin/` bundle rather than the bare watcher,
  because the watcher imports its sibling paths module; the copy on the other
  machine now lives in one deterministic scratch directory under `/tmp` instead
  of a file, and nothing accumulates across reconnects.
- `python3 scripts/check-portability.py` builds a foreign machine in a temporary
  directory (its own `HERMES_HOME`, `XDG_*` directories and bot names) and checks
  every one of those cases; CI runs it on a runner with neither Omarchy nor
  Hermes installed, so an assumption about the author's machine fails there.

## 0.3.1

- Fixed: switching the instance in the Hermes Desktop window left the bar on the
  old one. The field the app moves on a switch is `lastUsed` in
  `connections.json` - its own registry documents it as "the last source the
  Sessions workspace successfully opened" - while `primary` only moves when you
  make a connection primary. Measured by watching the file through a switch:
  `primary` unchanged, `lastUsed` flipped to the host and back. The widget now
  follows `lastUsed`, and only falls back to `primary` when it is absent.
- A URL + token gateway connection cannot be read yet, so the bar keeps this
  machine's roster - and now says so in the panel header (`HERMBOT - <name>
  (remote) - local only`) instead of passing it off as the window's.

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

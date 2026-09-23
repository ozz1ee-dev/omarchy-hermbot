# Changelog

## 0.8.0

- **Take a conversation to Herdr.** The row under the cursor offers `herdr` - the
  open chat has one in its header, and `Shift+H` does the same from the roster - and it
  shows you that conversation in [Herdr](https://herdr.dev): raising the pane when
  it is already running, and otherwise making a tab, starting `hermes` on that exact
  session, and bringing the Herdr window forward. The conversation is addressed by
  session id, never by title, because the roster elides titles with an ellipsis. It
  is offered only while the roster is read from this machine: a remote session id
  names a session no pane here can run. A jump closes the panel - the conversation
  has moved to the terminal, and Hermes allows one writer per session.

### Fixed

- **The jump lands on the exact conversation, or opens it.** A pane is matched by
  the session id alone. The profile is never a fallback: several idle panes can
  share one, and switching to any of them opened a different thread - which is
  exactly what "it does not go to the right conversation" was. When no pane runs
  the session it is opened, and a tab this widget already made for it (its label
  names the profile and the conversation) is reused rather than duplicated.
- **A bare `h` no longer blurs the panel.** The framework's key catcher claims `h`
  as "move left" before any text key is handed to the widget, and the widget had
  wired "move left" to the privacy scrub - so `h` turned every label into noise.
  The scrub is an IPC-only aid now (`omarchy-shell ozz1ee.hermbot scrub`), and the
  Herdr jump sits on `Shift+H`, which the catcher leaves alone.

## 0.7.0

- **Pick the instance from the panel.** `s` opens a list of every instance this install
  can be pointed at - this device, and each SSH connection Hermes Desktop knows - with
  the one in force marked and under the cursor, so Enter alone keeps it. `j`/`k` walk it,
  a click picks, `Esc` backs out. It replaces a blind toggle between two states with a
  list that names them.
- **The header names the instance, always.** Which machine the roster came from is the
  one thing the list cannot show by itself, and a pinned source is now called pinned -
  the difference between following the app and being pinned to a host is invisible until
  the app moves and the widget does not.
- **A switched instance answers immediately.** The watcher is bounced 120ms after a
  deliberate switch instead of waiting out the five-second debounce that exists for
  load-time cascades. Measured end to end: 344ms to the local roster, 924ms to a remote
  one - and the second is SSH agreeing to talk, not something waiting.
- **`1 bot`, not `1 bots`.**

### Fixed

- **A turn that outlives its own lease no longer looks like a free session.** A turn
  lease carries a seven-minute expiry and nothing renews it, so a long turn read as
  expired: the widget treated the session as free, sent into it, the backend refused with
  exit code 1, and the window said nothing - because the turn it believed was over was
  still running. The presence of the lease plus a live owner is what counts now, and the
  expiry is a fallback only for a row with no pid to ask about.
- **The unread count can no longer be stuck above every future count.** A session's
  message count FALLS when it is compacted, and the panel's watermark could only ever
  rise, so it sat above every count the session would report again and the badge was dead
  for good. It is set now, not merely raised.
- **The unread count stops clearing itself.** A chat that was not waiting was treated as
  a chat that had been read, so every badge died the moment a turn ended. Only reads move
  the mark: this window showing the thread, and the desktop's own watermark.
- **The badge is drawn where it can be seen.** It was laid out on a second line of a
  fixed-height row and clipped away every time - the binding said visible, the probe said
  the row carried the count, and nothing appeared on screen. It sits inline with the
  row's time now.
- **The setting is `instance`, not `source`.** A bar item already has a `source` field -
  the widget's own QML path - and a setting written under that name replaced the path,
  after which the shell had nothing to load and the plugin disappeared from the bar with
  no line in the journal. A pick can also no longer persist an address the list never
  offered.

## 0.6.0

- **The chat window resizes by its edges.** Grab the right edge, the bottom edge or the
  bottom-right corner grip: the window grows around its own centre, because the panel surface centres
  itself horizontally - one edge moves, both sides change. The transcript stops
  re-wrapping while you drag and settles once you let go, so the drag stays smooth.
- **Text size on `Ctrl+=` / `Ctrl+-`, `Ctrl+0` to put it back.** 75% to 180% in steps of
  ten, the panel's inside only: the bar's label and avatar keep the theme's size, so
  raising the text never disturbs the bar.
- **A queued message drains itself.** Hermes allows one writer per session, so a message
  typed while the bot is mid-turn is queued rather than refused. It used to wait for a
  read to notice the chat was free, which could take as long as the turn; a pump of its
  own now sends it within about a second of the lease being released.
- **`held by CLI` clears when the turn ends, not when the process does.** The window read
  the process registry, which lives as long as the process does - so a finished turn
  could look busy for minutes. It reads the turn lease instead, which is deleted the
  moment the turn ends.
- **No send button.** Enter sends and Shift+Enter breaks the line, so the button only
  ever duplicated the key your hand was already on, and it cost the field a strip of
  width. The field is wider for it.
- **A bigger window by default**, and `**bold**` and `code` in a reply are drawn as bold
  and code rather than as asterisks and backticks.

### Fixed

- **The preview of an image you send.** Hermes records an attachment as a bracketed
  `[Image attached at: ...]` line, which the window did not recognise: the raw path was
  printed as if it were the message. It is read now, and drawn as the picture it is.
- **An image path that cannot be loaded retried forever.** Ordinary message text that
  happened to look like a path - a reply explaining the marker above, for instance - was
  drawn as an image, and a failed load retries. The shell sat at 80-90% of a core with
  the chat open, which is what made the window feel heavy. A path must now be absolute,
  end in an image suffix, and the bracketed form is read from your turns only. A failed
  load stops instead of retrying.
- **The reply no longer appears twice while it streams.** The store can already carry a
  prefix of a reply that is still arriving, and both copies were drawn - once with a
  clock, once without. The stored copy is now hidden while the live text shows the same
  words, instead of the live text being cleared: clearing it made the words vanish
  mid-sentence and the view jump.
- **The transcript is only rebuilt when it changed.** The pump reads about once a second,
  and every read used to rebuild every row - which twitched the view and cost a layout of
  the whole conversation. Measured over ten seconds: seven reads, zero rebuilds.
- **Fewer rows drawn, and a collapsed work row lays out 4000 characters, not 90 000.**
  The window held ~800 MB and half a core with a long conversation open; the drawn rows
  are bounded now.

## 0.5.0

- **You can talk to a bot from the panel now, with Hermes Desktop not involved.**
  A bot row opens a chat window in place of the roster: `n` starts a fresh chat with
  the bot under the cursor, `Esc` goes back, and the header names the bot being
  talked to. The turn is handed to Hermes exactly as the desktop hands it over -
  `@file:` and `@image:` references in the message, the text through `--query-file`,
  every process spawned as argv - so nothing is re-implemented on this side and no
  shell is involved anywhere.
- **The bot's work is in the stream, live while the turn runs.** Thinking blocks, one
  line per tool call and one per result, errors included. The answer lands in one
  piece several seconds after you send, so without this the wait is a spinner; with
  it the call that produced the answer appears as it happens, and the same detail is
  read back from the session store afterwards. `w`, or the header's `stream on` /
  `stream off`, folds it back to a plain conversation, saved.
- **Attach files, with a real preview.** `+` opens a file browser *inside the panel*
  and what you pick becomes a chip above the input, with a thumbnail when it is an
  image. In-panel on purpose: the panel is a full-screen surface on the overlay
  layer, so a separate chooser can only ever appear underneath it and takes focus
  with it.
- **A bot row talks in the bot's own canonical Bot Chat.** Hermes allows one writer
  per session, and the desktop holds that lease while a chat is open in it. The row
  therefore targets the conversation the desktop keeps out of its sidebar - the one
  nothing else holds - and a session row that does target a desktop-held chat says
  so in the window instead of failing on a refusal.
- **Demo mode stages the conversation as well as the roster.** The demo sessions are
  in no store, so reading one returned nothing and the chat window showed an empty
  conversation - useless as a demo and useless for a screenshot. It now fills the
  window with a staged turn, and the read error that used to sit under the input box
  is suppressed while demo mode is on.
- **Fixed: the panel's keys stopped answering after leaving the chat window.** The
  chat's input held the keyboard focus, and going back to the roster left it on an
  item that was by then hidden, so `n`, `r`, `p` and `s` all did nothing - with no
  error in the log to say why. Focus now returns to the panel's key catcher when the
  chat closes. Measured with synthetic key presses: from a clean roster both worked;
  after leaving a chat, both were dead.
- **Fixed: `stream off` still showed the work while the turn ran.** The switch cut
  the work out of the store read but not out of the live stream, so turning it off
  meant "visible while it runs, gone the moment it ends" - which reads as a glitch,
  not a setting. Both views obey the same switch now.
- **The footer is two lines, and no longer advertises a key that does nothing.** The
  list of keys had outgrown the card and could only ever be elided; it is split by
  role now - what you press to act, then what the panel is currently set to, so the
  second line doubles as a readout of the order, the source and the bar metric. `h`
  was listed there and had no handler anywhere in the file, while `o` worked and was
  not listed at all. The space under the footer was measured at more than twice the
  space above the header and is now near-symmetric.
- **`showWork` became a setting, and the chat window gained probes.** Seven settings
  now. `chatState`, `newChat`, `closeChat`, `openThread`, `picker` and `attach` join
  the IPC surface, because the chat window is otherwise reachable only by clicking -
  which is also how the screenshots in the README were taken.
- **The README was brought back in line with the code.** It still claimed the panel
  had no input, listed a key with no handler, counted six settings, and described a
  footer that shortens as the panel narrows. None of that is true any more, and a
  description that disagrees with the code is worse than no description.

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

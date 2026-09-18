import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Derived from Rakabot (https://github.com/ozz1ee-dev/omarchy-rakabot),
// Copyright 2026 ozz1ee, Apache-2.0, which is derived from omabot
// (https://github.com/njpatel/omabot), Copyright Neil Patel, Apache-2.0.
// Changed for Hermbot: the roster is read from the local Hermes install
// instead of Rakazo's RPC API, the palette/shape list are Hermes' ui_meta, the
// actions open Hermes on a bot's conversation, the settings keys are the
// plugin's, and section grouping is the gateway grouping the payload
// carries. The bar cluster, the panel geometry, the row layout, the avatar
// row layout, the avatar drawing, the expressions and every animation are
// Rakabot's unchanged.
//
// Hermbot: your Hermes Bot Mode roster in the Omarchy bar. bin/hermbot-watch
// reads the same files the desktop writes and streams them; this renders each bot
// as its own avatar - the shape and colour it carries in ui_meta - with an
// expression for its state: alert when it is waiting on you, curious when it has
// something unread, excited while it is active. Keys: j/k move ·
// Enter focus the app · h redact · r cycle the bar text · g group by
// gateway · Esc close.

Panel {
  id: root
  moduleName: "ozz1ee.hermbot"
  ipcTarget: "ozz1ee.hermbot"
  manageIpc: false

  // ---------------------------------------------------------------- settings
  // The mark is always in the bar. This is only what sits beside it:
  // the bots that want you, drawn as themselves; how many there are; or nothing.
  property string barMetric: {
    var v = String(setting("barMetric", "avatars"))
    return barMetrics.indexOf(v) >= 0 ? v : (v === "count" ? "count" : "avatars")
  }
  readonly property var barMetrics: ["avatars", "count", "none"]
  // persist=false changes it for this session only. Writing the bar entry
  // reloads the widget, which would throw away anything held in memory - the
  // demo roster included - so a scripted walk through the states asks for it.
  function cycleBarMetric(persist) {
    barMetric = barMetrics[(barMetrics.indexOf(barMetric) + 1) % barMetrics.length]
    if (persist !== false)
      Quickshell.execDetached(["omarchy", "bar", "set", "ozz1ee.hermbot", "barMetric", barMetric])
  }

  // attention: whoever wants you first (oldest wait first, so nobody is
  // buried), a rule, then everyone else by recency. gateway: the grouping the
  // payload actually carries - what the gateway serves, and what it does not.
  // flat: purely by recency. Session-only: none of the three is a settings key.
  property string ordering: String(setting("ordering", "attention"))
  readonly property var orderings: ["attention", "gateway", "flat"]
  function cycleOrdering() {
    ordering = orderings[(orderings.indexOf(ordering) + 1) % orderings.length]
    // Persisted the way Rakabot persists it, so a restart keeps the order you
    // picked instead of snapping back to attention.
    Quickshell.execDetached(["omarchy", "bar", "set", "ozz1ee.hermbot", "ordering", ordering])
    cursor = 0
  }

  readonly property int maxBarAvatars: Math.max(1, Math.min(6, Number(setting("maxBarAvatars", 3))))
  readonly property string watcher: Qt.resolvedUrl("bin/hermbot-watch").toString().replace(/^file:\/\//, "")
  readonly property string opener: Qt.resolvedUrl("bin/hermbot-open").toString().replace(/^file:\/\//, "")

  // Notifications when a bot writes or starts waiting for you. These belong to the
  // watcher: it is the only thing that sees a transition, and it owns the state
  // file that keeps one card per bot. Hermes' own cards are left to Hermes.
  property bool notifyOnMessage: String(setting("notifyOnMessage", "true")) !== "false"

  // The pinned section: the desktop's own Pinned, grouped by the bot it belongs
  // to. On by default; `p` flips it and the choice is saved.
  property bool showPinned: String(setting("showPinned", "true")) !== "false"

  // Which instance to follow: "auto" is Hermes Desktop's own connection, so the
  // bar holds the roster of whatever the app is on - this machine, or the SSH
  // host it is pointed at. "local" pins it to this machine.
  property string source: String(setting("source", "auto"))

  function setting(name, fallback) {
    var s = root.settings || ({})
    return s[name] !== undefined && s[name] !== null ? s[name] : fallback
  }

  // ---------------------------------------------------------------- theme
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.45)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.20)
  readonly property color divider: Qt.rgba(fg.r, fg.g, fg.b, 0.34)
  readonly property color hilite: Qt.rgba(fg.r, fg.g, fg.b, 0.09)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color eyeInk: Color.background

  // ---------------------------------------------------------------- state
  property var liveSnap: null
  readonly property var snap: demoMode ? demoSnap : liveSnap

  // A staged roster for screenshots and for showing the thing off, using the
  // profiles a Hermes install actually carries. One bot wants you, two are
  // active; ages are relative to when demo mode was switched on.
  property bool demoMode: false
  property double demoStart: 0
  property bool demoNeedsHelp: true
  readonly property var demoSnap: {
    var t = (demoStart || Date.now()) / 1000
    var ago = function(mins) { return t - mins * 60 }
    var bot = function(name, title, shape, color, unread, waiting, active, mins, text, fromBot) {
      return { name: name, handle: "@" + name, title: title, description: "",
               shape: shape, color: color, image_kind: "shape", custom: true, created: null,
               gateway_served: true, waiting: waiting, active: active, activity_at: ago(mins),
               chat: { session_id: "demo_" + name, exists: true, hidden: true, pinned: false,
                       archived: false, message_count: 40 + (mins % 90),
                       last_activity_at: ago(mins), last_read_at: null, unread: unread > 0,
                       preview: text, preview_role: fromBot ? "assistant" : "user",
                       preview_ts: ago(mins), from_bot: fromBot },
               recent_session: { session_id: "demo_r_" + name, title: null, last_activity_at: ago(mins) },
               newest_session_id: "demo_r_" + name, hermes_cmd: "hermes -p " + name + " chat",
               open: { session_id: "demo_" + name, deep_link: "", recent_deep_link: "" } }
    }
    // The shapes are the ones Hermes' own avatar picker ships - the legacy set
    // and the blobatar kinds - so the demo shows what a real roster can hold
    // rather than something ui_meta could never produce.
    // Each staged bot also carries the session it is in (or the last one it
    // finished) and a few pinned chats, both in English like the rest of the
    // demo, so a screenshot shows the whole panel rather than two thirds of it.
    var withThreads = function(b, attachTitle, attachMode, pinned) {
      b.attach = { session_id: "demo_a_" + b.name, title: attachTitle,
                   last_activity_at: b.chat.last_activity_at, ended: attachMode !== "live",
                   message_count: 24, deep_link: "" }
      b.attach_mode = attachMode
      b.pinned = []
      for (var i = 0; i < pinned.length; i++) {
        b.pinned.push({ session_id: "demo_p_" + b.name + "_" + i, title: pinned[i][0],
                        last_activity_at: ago(pinned[i][1]), ended: pinned[i][1] > 240,
                        message_count: 30 + i, deep_link: "" })
      }
      return b
    }
    var bots = [
      withThreads(bot("dev", "Dev - Local", "blobatar::round", "#dd4b66", 0, demoNeedsHelp, true, 34,
          "Both watchers ran at once and the lock held. The race is real, and it is closed."),
          "Lock test: two watchers, one lock", "live",
          [["Plugin roadmap", 40], ["Bar widget design", 180], ["Release checklist", 1500]]),
      withThreads(bot("default", "Hermes - Local", "squircle", "#8b5cf6", 2, false, false, 12,
          "Three bots on this machine. Want me to draft the release notes?", "@dev"),
          "Release notes draft", "closed",
          [["Homelab runbook", 300], ["Model choices", 2880]]),
      withThreads(bot("web", "Web - Local", "blobatar::sun", "#f59e0b", 1, false, false, 5,
          "The gateway restarted cleanly and both sockets are back."),
          "Digest sources", "live", [["Reading list", 600]]),
      withThreads(bot("research", "Research - Local", "cloud", "#10b981", 0, false, true, 3,
          "Six papers shortlisted; two are the same result reported twice."),
          "Paper shortlist", "live", [["Methods review", 120]]),
      withThreads(bot("ops", "Ops - Local", "blobatar::cloud", "#06b6d4", 0, false, false, 88,
          "Backups are four days behind and the NAS scrub finished clean."),
          "Backup audit", "closed", [["NAS scrub log", 1440]]),
      withThreads(bot("notes", "Notes - Local", "hexagon", "#eab308", 0, false, false, 210,
          "Filed the meeting notes under the project they belong to."),
          "Meeting notes: Q3 planning", "closed", [])
    ]
    var pinnedTotal = 0
    for (var p = 0; p < bots.length; p++) pinnedTotal += bots[p].pinned.length
    return {
      generated_ts: t, source: "demo",
      gateway: { pid: 0, running: true, state: "running", profiles: ["default", "dev", "web"] },
      counts: { bots: bots.length, waiting: demoNeedsHelp ? 1 : 0, active: 2, no_chat: 0,
                pinned: pinnedTotal },
      bots: bots
    }
  }
  function toggleDemo() {
    demoArrivalTimer.stop()
    demoNeedsHelp = true
    demoStart = Date.now()
    demoMode = !demoMode
    cursor = 0
    if (opened) requestGreeting(false)
  }
  Timer { id: demoArrivalTimer; interval: 1000; onTriggered: root.demoNeedsHelp = true }
  property bool scrub: false
  property int cursor: 0
  property double nowMs: Date.now()

  readonly property var counts: snap && snap.counts ? snap.counts : ({})
  readonly property var bots: snap && snap.bots ? snap.bots : []
  readonly property var gateway: snap && snap.gateway ? snap.gateway : ({})
  // Which instance this roster came from, and whether it answered at all: the
  // watcher follows Hermes Desktop's own connection, so the panel has to say
  // whose bots it is showing.
  readonly property string instanceLabel: String(snap && snap.instance ? snap.instance : "")
  readonly property bool remoteSource: !!(snap && snap.source && String(snap.source).indexOf("local") !== 0)
  readonly property string sourceError: snap && snap.error ? String(snap.error) : ""
  // The window sits somewhere this widget cannot read (a URL + token gateway):
  // the roster is this machine's, so the header has to say that out loud.
  readonly property string sourceWarning: snap && snap.source_warning ? String(snap.source_warning) : ""
  readonly property bool gatewayUp: !!gateway.running
  readonly property bool alarming: (counts.waiting || 0) > 0
  readonly property int unreadBots: {
    var n = 0
    for (var i = 0; i < bots.length; i++) if (bots[i].chat && bots[i].chat.unread) n++
    return n
  }
  readonly property bool attention: alarming || unreadBots > 0

  // Bots that want you, most recently active first: the bar shows these.
  readonly property var wanting: {
    var out = []
    for (var i = 0; i < bots.length; i++) {
      var b = bots[i]
      if (b.waiting || b.active || (b.chat && b.chat.unread)) out.push(b)
    }
    var rank = function(x) { return x.waiting ? 0 : (x.active ? 1 : 2) }
    out.sort(function(a, b) {
      if (rank(a) !== rank(b)) return rank(a) - rank(b)
      return (b.activity_at || 0) - (a.activity_at || 0)
    })
    return out
  }

  // The gateway groups the roster, and that is the only grouping the payload
  // carries: what it serves, and what it does not. Hermes writes each bot's
  // profile on this machine, so in practice there is one group - which is the
  // truth, and the header says so rather than inventing sections.
  readonly property var sections: {
    var served = [], rest = []
    for (var i = 0; i < bots.length; i++) (bots[i].gateway_served ? served : rest).push(bots[i].name)
    var out = []
    if (served.length > 0) out.push({ id: "gateway", name: "GATEWAY", count: served.length, bot_ids: served })
    if (rest.length > 0) out.push({ id: "local", name: "LOCAL", count: rest.length, bot_ids: rest })
    return out
  }

  // Expression carries state. Gone quiet for a week does say something, so that
  // is what dozes; a bot in the middle of a conversation is the awake one.
  readonly property double staleAfterS: 7 * 24 * 3600
  function faceFor(b) {
    var chat = b.chat || ({})
    if (b.waiting) return "attentive"
    if (chat.unread && b.active) return "excited"
    if (chat.unread) return "curious"
    if (b.active) return "happy"
    if (b.activity_at && (nowMs / 1000 - b.activity_at) > staleAfterS) return "drowsy"
    return "neutral"
  }
  function colorFor(b) { return b.color ? b.color : dim }

  // The bot list itself, before the rows that hang off it. Three orderings, all
  // of them rebuilt whenever the view changes.
  readonly property var rowsBase: {
    var out = []
    if (!snap) return out
    if (ordering === "attention") {
      var wants = [], rest = []
      for (var b = 0; b < bots.length; b++) {
        var bot = bots[b]
        ;(bot.waiting || (bot.chat && bot.chat.unread) ? wants : rest).push(bot)
      }
      // Waiting longest first: the one that has been ignored most deserves the top.
      wants.sort(function(x, y) { return (x.activity_at || 0) - (y.activity_at || 0) })
      rest.sort(function(x, y) { return (y.activity_at || 0) - (x.activity_at || 0) })
      for (var w = 0; w < wants.length; w++) out.push({ kind: "bot", bot: wants[w] })
      if (wants.length > 0 && rest.length > 0) out.push({ kind: "rule" })
      for (var r2 = 0; r2 < rest.length; r2++) out.push({ kind: "bot", bot: rest[r2] })
      return out
    }
    if (ordering === "gateway" && sections.length > 0) {
      var byName = ({})
      for (var i = 0; i < bots.length; i++) byName[bots[i].name] = bots[i]
      for (var s = 0; s < sections.length; s++) {
        var ids = sections[s].bot_ids || []
        if (ids.length === 0) continue
        out.push({ kind: "section", name: sections[s].name, count: ids.length })
        for (var k = 0; k < ids.length; k++) if (byName[ids[k]]) out.push({ kind: "bot", bot: byName[ids[k]] })
      }
    } else {
      var sorted = bots.slice().sort(function(a, b) {
        return (b.activity_at || 0) - (a.activity_at || 0)
      })
      for (var j = 0; j < sorted.length; j++) out.push({ kind: "bot", bot: sorted[j] })
    }
    return out
  }
  // What the list actually is: each bot, then the one session that belongs under
  // it (the chat it is in, or the last one it finished), and - at the end - the
  // pinned chats again, grouped by the bot they belong to. Exactly the desktop's
  // own arrangement, where a pinned chat is its own section and never a second
  // copy of a row.
  readonly property var rows: {
    var base = rowsBase
    var out = []
    for (var i = 0; i < base.length; i++) {
      out.push(base[i])
      if (base[i].kind === "bot" && base[i].bot.attach) {
        out.push({ kind: "attach", bot: base[i].bot, session: base[i].bot.attach,
                   mode: base[i].bot.attach_mode })
      }
    }
    if (!showPinned) return out
    var groups = []
    for (var j = 0; j < bots.length; j++) {
      if (bots[j].pinned && bots[j].pinned.length > 0) groups.push(bots[j])
    }
    if (groups.length === 0) return out
    out.push({ kind: "pinnedHeader" })
    for (var g = 0; g < groups.length; g++) {
      out.push({ kind: "pinnedAgent", bot: groups[g] })
      for (var k = 0; k < groups[g].pinned.length; k++) {
        out.push({ kind: "pinned", bot: groups[g], session: groups[g].pinned[k] })
      }
    }
    return out
  }

  // Rows the cursor can land on: the bots and every session row under them. A
  // heading is not a destination.
  readonly property var botRows: {
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var kind = rows[i].kind
      if (kind === "bot" || kind === "attach" || kind === "pinned") out.push(i)
    }
    return out
  }

  // ---------------------------------------------------------------- watcher
  Process {
    id: watcherProc
    // --notify is a bare flag here, not an argument: the watcher decides what a
    // transition is and owns the state file that keeps one card per bot.
    command: root.notifyOnMessage
      ? [root.watcher, "--interval", "2", "--source", root.source, "--notify"]
      : [root.watcher, "--interval", "2", "--source", root.source]
    running: true
    stdout: SplitParser { onRead: function(data) { root.parseState(data) } }
    stderr: SplitParser {
      onRead: function(data) { if (String(data).trim() !== "") console.warn("hermbot", String(data).trim()) }
    }
    onExited: function(code) { console.warn("hermbot", "watcher exited", code); restartTimer.start() }
  }
  Timer { id: restartTimer; interval: 5000; onTriggered: watcherProc.running = true }
  // A settings change has to land on the command line, and a running Process
  // will not pick up a new command: bounce it.
  onNotifyOnMessageChanged: { watcherProc.running = false; restartTimer.restart() }
  onSourceChanged: { watcherProc.running = false; restartTimer.restart() }

  function parseState(text) {
    try {
      var parsed = JSON.parse(String(text || ""))
      if (parsed && typeof parsed === "object" && Array.isArray(parsed.bots)) {
        root.liveSnap = parsed
        root.nowMs = Date.now()
      }
    } catch (e) {
      console.warn("hermbot", "bad state line", e)
    }
  }

  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: root.nowMs = Date.now() }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    cursor = 0
    panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    requestGreeting(false)
  }


  // Rows greet themselves when this fires: each avatar owns its own timing,
  // so there is no central loop to fall out of step with the list.
  signal greetRequested(bool everyone)

  // The bar's own avatars look up when the pointer arrives, before the panel
  // is even open. Same shape as the panel's greeting: each one hears the
  // signal and owns its own timing.
  signal barGreeted()
  // Shifts which flourish each position gets, so the same three bots do not
  // do the same three things every time you pass the bar.
  property int barGreetSeed: 0

  Timer {
    id: greetOnOpen
    interval: 260
    onTriggered: root.greetRequested(greetEveryone)
    property bool greetEveryone: false
  }
  function requestGreeting(everyone) {
    dealFlourishes()
    greetOnOpen.greetEveryone = !!everyone
    greetOnOpen.restart()
  }

  // Greetings deal from a shuffled deck rather than rolling independently, so
  // three bots never all hop at once. Past a full deck it reshuffles, and it
  // will not repeat the card that was just played across that seam.
  property var flourishDeck: []
  property int flourishCount: 6
  property int lastFlourish: -1
  function dealFlourishes() {
    var deck = []
    for (var i = 0; i < flourishCount; i++) deck.push(i)
    for (var j = deck.length - 1; j > 0; j--) {
      var k = Math.floor(Math.random() * (j + 1))
      var t = deck[j]; deck[j] = deck[k]; deck[k] = t
    }
    if (deck.length > 1 && deck[deck.length - 1] === lastFlourish) {
      var swap = deck[0]; deck[0] = deck[deck.length - 1]; deck[deck.length - 1] = swap
    }
    flourishDeck = deck
  }
  function nextFlourish() {
    if (!flourishDeck || flourishDeck.length === 0) dealFlourishes()
    var deck = flourishDeck
    var pick = deck.pop()
    flourishDeck = deck
    lastFlourish = pick
    return pick
  }

  // Open Hermes on a bot. bin/hermbot-open walks its own ladder - the packaged
  // Electron binary with the bot's deep link (a running app picks it up through
  // its single-instance handler, a cold app boots on it), then xdg-open, then
  // raising the window - so tapping a bot never opens a second copy of a window
  // you already have. --focus also raises it.
  function openBot(bot) {
    if (!bot) return
    Quickshell.execDetached([root.opener, "--bot", String(bot.name), "--focus"])
    root.close()
  }

  // A session row - the one hanging off a bot, or one of its pinned chats. These
  // are ordinary visible sessions, so the plain session deep link opens them; the
  // name-addressed door is only needed for the hidden Bot Chat.
  function openSession(bot, session) {
    if (!bot || !session) return
    Quickshell.execDetached([root.opener, "--bot", String(bot.name),
                             "--session", String(session.session_id), "--focus"])
    root.close()
  }

  function togglePinned() {
    showPinned = !showPinned
    Quickshell.execDetached(["omarchy", "bar", "set", "ozz1ee.hermbot", "showPinned",
                             showPinned ? "true" : "false"])
    cursor = 0
  }

  // auto follows Hermes Desktop's connection; local pins the bar to this machine.
  function cycleSource() {
    source = source === "auto" ? "local" : "auto"
    Quickshell.execDetached(["omarchy", "bar", "set", "ozz1ee.hermbot", "source", source])
    cursor = 0
  }

  // Enter lands on whatever the cursor is on: a bot opens the bot, a session row
  // opens that session.
  function activateRow(index) {
    if (index < 0 || index >= rows.length) return
    var row = rows[index]
    if (row.kind === "bot") root.openBot(row.bot)
    else if (row.kind === "attach" || row.kind === "pinned") root.openSession(row.bot, row.session)
  }

  function clickRow(index) {
    var row = rows[index]
    if (!row) return
    if (row.kind !== "bot" && row.kind !== "attach" && row.kind !== "pinned") return
    root.cursor = index
    root.activateRow(index)
  }

  // The plain "open Hermes" path: the mark, a right-click, or a heading. The
  // opener has no bot-less form, so it lands on whoever wants you most.
  function focusTop() { if (bots.length > 0) root.openBot(bots[0]) }


  // The bot under the cursor, when the cursor is on a bot rather than a heading.
  readonly property var cursorBot: {
    if (cursor < 0 || cursor >= rows.length) return null
    return rows[cursor].kind === "bot" ? rows[cursor].bot : null
  }

  IpcHandler {
    // Omarchy instantiates a bar widget more than once (a hidden copy is used
    // for measurement), and both copies would register for the same target -
    // the loser silently drops every call. Only the copy actually mounted in a
    // bar takes the name, so `omarchy-shell ozz1ee.hermbot …` reaches the one
    // on screen.
    enabled: root.bar !== null
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function scrub(): string { root.scrub = !root.scrub; return root.scrub ? "scrubbed" : "clear" }
    function group(): string { root.cycleOrdering(); return root.ordering }
    function order(mode: string): string { root.ordering = mode; return root.ordering }
    // A staged roster for screenshots; call again to go back to the real one.
    function demo(): string {
      root.toggleDemo()
      if (root.demoMode && !root.opened) root.open()
      return root.demoMode ? "demo roster" : "live roster"
    }
    function demoAssistance(): string {
      if (!root.demoMode) root.toggleDemo()
      root.close()
      root.demoNeedsHelp = false
      demoArrivalTimer.restart()
      return "the dev bot will ask for help in one second"
    }
    // Play the greeting on demand: every bot, whether or not it has news.
    // Opens the panel first, because a panel loses focus - and closes - the
    // moment you type the command in a terminal.
    function greet(): string {
      if (!root.opened) root.open()
      root.requestGreeting(true)
      root.barGreetSeed += 1
      root.barGreeted()
      return "greeting"
    }
    function geometry(): string {
      return JSON.stringify({ x: panel.cardOrigin.x, y: panel.cardOrigin.y, w: panel.contentWidth, h: panel.contentHeight })
    }
    function metric(): string { root.cycleBarMetric(false); return root.barMetric }
    // Stage the pinned section for a screenshot, or check it without a keyboard.
    function pinned(): string { root.togglePinned(); return root.showPinned ? "pinned shown" : "pinned hidden" }
    // Aim the eyes at a point in the panel, in its own coordinates. The eyes
    // follow a real pointer; this is how a recording without one drives them.
    function look(x: int, y: int): string {
      keyCatcher.pointerAt(x, y)
      return x + "," + y
    }
    function away(): string { keyCatcher.pointerGone(); return "away" }
    function state(): string {
      return JSON.stringify({ counts: root.counts, gateway: root.gateway, bots: root.bots.length,
        barEdge: root.barEdge, barAvatars: barAvatarModel.count })
    }
  }

  // ---------------------------------------------------------------- helpers
  function fmtAgo(ts) {
    if (!ts) return ""
    var s = Math.max(0, nowMs / 1000 - ts)
    if (s < 90) return "now"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h"
    var d = Math.floor(h / 24)
    return d < 7 ? d + "d" : Math.floor(d / 7) + "w"
  }
  function noise(text) {
    var glyphs = "░▒▓█▓▒", h = 2166136261, out = ""
    for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = (h * 16777619) >>> 0 }
    for (var j = 0; j < text.length; j++) {
      h ^= h << 13; h >>>= 0; h ^= h >>> 17; h ^= h << 5; h >>>= 0
      out += glyphs.charAt(h % glyphs.length)
    }
    return out
  }
  function label(text) { text = String(text || ""); return scrub ? noise(text) : text }

  // The newest thing said, and who said it. A row's one-liner names the sender
  // only when a bot wrote it: hearing about your own message twice is noise.
  function lastActivity(bot) {
    var chat = bot && bot.chat ? bot.chat : ({})
    return chat.last_activity_at || (bot ? bot.activity_at : 0) || 0
  }
  function previewOf(bot) {
    var chat = bot && bot.chat ? bot.chat : ({})
    var text = chat.preview ? String(chat.preview) : ""
    return text.replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  }
  function senderOf(bot) {
    var chat = bot && bot.chat ? bot.chat : ({})
    if (chat.from_bot) return String(chat.from_bot)
    if (chat.preview_role === "user") return "you"
    return ""
  }
  function rowPreview(bot) {
    var body = root.previewOf(bot)
    if (body === "") return (bot && bot.chat && bot.chat.exists === false)
      ? "no Bot Chat yet" : "nothing said yet"
    var who = root.senderOf(bot)
    return who !== "" ? who + " \u00b7 " + body : body
  }

  function moveCursor(delta) {
    if (botRows.length === 0) return
    var at = botRows.indexOf(cursor)
    if (at < 0) { cursor = botRows[0]; return }
    cursor = botRows[Math.max(0, Math.min(botRows.length - 1, at + delta))]
    ensureVisible()
  }
  function ensureVisible() {
    var item = repeater.itemAt(cursor)
    if (!item) return
    if (item.y < panelFlick.contentY) panelFlick.contentY = Math.max(0, item.y - Style.space(8))
    else if (item.y + item.height > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height,
                                     item.y + item.height - panelFlick.height + Style.space(8))
  }

  // ---------------------------------------------------------------- bar
  // In count mode: how many bots want you. Nothing when nobody does, so the
  // bar stays quiet; in avatars mode the faces say it instead.
  readonly property int wantingCount: wanting.length
  readonly property string barText: {
    if (!snap || vertical || barMetric !== "count") return ""
    return wantingCount > 0 ? String(wantingCount) : ""
  }
  readonly property string barTooltip: {
    if (!snap) return "Hermbot"
    if (!gatewayUp) return "Hermes: gateway not running"
    var c = counts
    var text = (c.bots || 0) + " bots · " + (c.waiting || 0) + " waiting on you · "
      + (c.active || 0) + " active · " + root.unreadBots + " unread"
    if ((c.no_chat || 0) > 0) text += " · " + c.no_chat + " without a chat"
    return text
  }

  implicitWidth: vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : row.implicitWidth
  implicitHeight: vertical ? row.implicitHeight : (bar ? bar.barSize : Style.bar.sizeHorizontal)
  readonly property real openPanelIndicatorWidth: row.width
  readonly property real openPanelIndicatorHeight: row.height

  // What the bar draws beside the logo. Nothing waiting means nothing beside
  // it - the logo alone is still the widget, and still opens the panel.
  readonly property bool vertical: !!(bar && bar.vertical)
  // Rakabot's guard, kept: with the source down the bar shows the mark alone
  // (dimmed) rather than avatars it cannot vouch for.
  readonly property var barAvatars: (!snap || !gatewayUp || barMetric !== "avatars")
    ? [] : wanting.slice(0, maxBarAvatars)
  readonly property string barEdge: bar ? bar.position : "top"

  // Keep delegates keyed by bot, rather than recreating every face on each
  // watcher snapshot. Only new slots make room and drop in.
  ListModel { id: barAvatarModel }
  onBarAvatarsChanged: syncBarAvatars()

  function syncBarAvatars() {
    var names = barAvatars.map(function(bot) { return bot.name })
    for (var i = barAvatarModel.count - 1; i >= 0; i--)
      if (names.indexOf(barAvatarModel.get(i).botName) < 0) barAvatarModel.remove(i)
    for (var j = 0; j < names.length; j++) {
      var at = j
      while (at < barAvatarModel.count && barAvatarModel.get(at).botName !== names[j]) at++
      if (at === barAvatarModel.count) barAvatarModel.insert(j, { botName: names[j] })
      else if (at !== j) barAvatarModel.move(at, j, 1)
    }
  }
  // The glyphs beside it carry their own optical padding; a mark drawn to the
  // full icon canvas would stand taller than all of them.
  readonly property real markSize: Math.round(Style.bar.iconCanvas * 0.82)
  // How far the row pulls back into the icon slot's padding, to bring what
  // follows the mark close enough to read as part of it.
  readonly property real barPull: Style.space(3)
  // Same parity as the mark, so both round their centre to the same pixel -
  // otherwise the avatars sit half a pixel below it, which reads as crooked.
  readonly property real barAvatarSize: {
    var h = Math.round(Style.font.caption * 1.15)
    return (h % 2) === (markSize % 2) ? h : h + 1
  }

  Grid {
    id: row
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 4
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
    // The icon slot is wider than the mark drawn inside it, which leaves as
    // much air after the mark as there is between whole widgets. Pull back
    // into that padding so the mark and what follows read as one thing.
    spacing: -root.barPull

    // The Hermbot mark, always. Drawn rather than loaded from the desktop's
    // icon so it takes the bar's colours like every other widget instead of
    // dropping a dark tile into the theme, and outlined so it carries the same
    // weight as the line glyphs beside it. Dimmed when the gateway is down.
    BarIconButton {
      id: button
      bar: root.bar
      text: "\u{f06a9}"
      onPressed: function(buttonCode) { root.barPressed(buttonCode) }
      iconComponent: Component {
        Item {
          Avatar {
            anchors.centerIn: parent
            width: root.markSize
            height: width
            shape: "squircle"
            outlined: true
            fill: root.bar ? root.bar.barForeground : root.fg
            eyeColor: root.bar ? root.bar.barForeground : root.fg
            face: "neutral"
            opacity: root.gatewayUp ? 1.0 : 0.45
            Behavior on opacity { NumberAnimation { duration: 220 } }
          }
        }
      }
    }

    // Along the bar: reserve the slot first, then enter from the screen edge.
    Item {
      id: avatars
      implicitWidth: root.vertical ? root.barAvatarSize : Math.max(0, avatarGrid.implicitWidth - Style.space(3))
      implicitHeight: root.vertical ? Math.max(0, avatarGrid.implicitHeight - Style.space(3)) : root.barAvatarSize
      width: implicitWidth
      height: implicitHeight
      visible: barAvatarModel.count > 0

      Grid {
        id: avatarGrid
        columns: root.vertical ? 1 : Math.max(1, barAvatarModel.count)

        Repeater {
          model: barAvatarModel
          Item {
            id: avatarSlot
            required property string botName
            required property int index
            readonly property var bot: {
              for (var i = 0; i < root.barAvatars.length; i++)
                if (root.barAvatars[i].name === botName) return root.barAvatars[i]
              return ({})
            }
            readonly property bool waiting: !!bot.waiting
            property bool ready: false
            property real spaceProgress: 0
            property real dropProgress: 0
            property real ink: 0
            readonly property real extent: (root.barAvatarSize + Style.space(3)) * spaceProgress
            width: root.vertical ? root.barAvatarSize : extent
            height: root.vertical ? extent : root.barAvatarSize

            Component.onCompleted: { ready = true; arrive.start() }
            // Already visible as active/unread? Its space exists: just settle
            // into the new attentive state, without shifting the neighbours.
            onWaitingChanged: if (ready && waiting && !arrive.running) drop.restart()

            SequentialAnimation {
              id: arrive
              NumberAnimation { target: avatarSlot; property: "spaceProgress"; to: 1; duration: 220; easing.type: Easing.OutCubic }
              ScriptAction { script: drop.restart() }
            }
            SequentialAnimation {
              id: drop
              // Hit the resting line, rebound towards the screen edge twice,
              // then pause on the bar before the one-shot attention wiggle.
              ParallelAnimation {
                NumberAnimation { target: avatarSlot; property: "dropProgress"; from: 0; to: 1; duration: 280; easing.type: Easing.InQuad }
                NumberAnimation { target: avatarSlot; property: "ink"; from: 0; to: 1; duration: 180 }
              }
              NumberAnimation { target: avatarSlot; property: "dropProgress"; to: 0.84; duration: 130; easing.type: Easing.OutQuad }
              NumberAnimation { target: avatarSlot; property: "dropProgress"; to: 1; duration: 150; easing.type: Easing.InQuad }
              NumberAnimation { target: avatarSlot; property: "dropProgress"; to: 0.945; duration: 100; easing.type: Easing.OutQuad }
              NumberAnimation { target: avatarSlot; property: "dropProgress"; to: 1; duration: 110; easing.type: Easing.InQuad }
              PauseAnimation { duration: 140 }
              ScriptAction { script: { if (avatarSlot.waiting) barAvatar.play(1) } }
            }

            Avatar {
              id: barAvatar
              width: root.barAvatarSize
              height: root.barAvatarSize
              shape: avatarSlot.bot.shape || "squircle"
              image: avatarSlot.bot.image ? "file://" + avatarSlot.bot.image : ""
              fill: root.colorFor(avatarSlot.bot)
              eyeColor: root.eyeInk
              face: root.faceFor(avatarSlot.bot)
              opacity: avatarSlot.ink
              transform: Translate {
                readonly property real distance: (1 - avatarSlot.dropProgress) * ((root.vertical ? root.width : root.height) + root.barAvatarSize)
                x: root.vertical ? (root.barEdge === "left" ? -1 : 1) * distance : 0
                y: root.vertical ? 0 : (root.barEdge === "bottom" ? 1 : -1) * distance
              }

              Connections {
                target: root
                function onBarGreeted() { if (!arrive.running && !drop.running) greet.restart() }
              }
              Timer {
                id: greet
                interval: 30 + avatarSlot.index * 90
                onTriggered: if (!arrive.running && !drop.running) barAvatar.playBold(avatarSlot.index + root.barGreetSeed)
              }
            }
          }
        }
      }
    }

    // Or, to its right: how many are waiting.
    Text {
      textFormat: Text.PlainText
      id: metric
      visible: root.barText !== ""
      text: root.barText
      color: root.alarming ? root.urgent : (root.bar ? root.bar.barForeground : root.fg)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Close the widget with as much air as the icon slot opens it with, so
    // whatever is beside the mark is not left flush against the next widget.
    // The pull-back applies here too, so add it back or the tail comes up
    // short of the head.
    Item {
      readonly property real padding: (avatars.visible || metric.visible)
        ? Math.round((button.width - root.markSize) / 2) + root.barPull : 0
      height: root.vertical ? padding : 1
      width: root.vertical ? 1 : padding
    }
  }

  MouseArea {
    anchors.fill: row
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) { root.barPressed(mouse.button) }
    onEntered: {
      if (root.bar) root.bar.showTooltip(row, root.barTooltip)
      root.barGreetSeed += 1
      root.barGreeted()
    }
    onExited: if (root.bar) root.bar.hideTooltip(row)
  }

  function barPressed(buttonCode) {
    if (buttonCode === Qt.RightButton) root.focusTop()
    else if (buttonCode === Qt.MiddleButton) root.cycleBarMetric()
    else root.toggle()
  }

  // ---------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: row
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(16), Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx < 0) root.scrub = !root.scrub
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateRow(root.cursor)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") root.cycleBarMetric()
        else if (t === "g" || t === "G") root.cycleOrdering()
        else if (t === "p" || t === "P") root.togglePinned()
        else if (t === "s" || t === "S") root.cycleSource()
      }

      // Where the pointer is, in panel coordinates. Avatars map it into their
      // own space and lean toward it; -1 means "not over the panel".
      property real pointerX: -1
      property real pointerY: -1

      function pointerAt(x, y) {
        pointerLeave.stop()
        pointerX = x
        pointerY = y
      }

      // Hover belongs to the topmost item, so crossing from a row onto a
      // separator - or between two rows - hands it over and reads as leaving.
      // Wait a moment before believing it: a real departure stays away, a
      // handover puts the pointer back within a frame or two, and the eyes
      // never snap forward for it.
      function pointerGone() { pointerLeave.restart() }

      Timer {
        id: pointerLeave
        interval: 260
        onTriggered: { keyCatcher.pointerX = -1; keyCatcher.pointerY = -1 }
      }

      MouseArea {
        id: pointerTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: function(mouse) { keyCatcher.pointerAt(mouse.x, mouse.y) }
        onExited: keyCatcher.pointerGone()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + Style.space(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          x: Style.space(4)
          width: parent.width - Style.space(8)
          spacing: 0

          // ---- header
          Item {
            width: parent.width
            height: header.implicitHeight + Style.space(10)
            Column {
              id: header
              width: parent.width
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                text: {
                  if (root.demoMode) return "HERMBOT · demo roster"
                  if (!root.snap) return "starting…"
                  if (root.sourceError) return "HERMBOT · " + root.sourceError
                  if (root.sourceWarning) return "HERMBOT · " + root.sourceWarning + " · local only"
                  if (!root.gatewayUp) return "HERMBOT · gateway down"
                  if (root.remoteSource) return "HERMBOT · " + root.instanceLabel
                  var profiles = root.gateway.profiles
                  return "HERMBOT · " + (profiles ? profiles.length : 0) + " profiles"
                }
                color: root.sourceError ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                visible: root.snap !== null
                text: {
                  var c = root.counts
                  var bits = [(c.bots || 0) + " bots"]
                  if ((c.waiting || 0) > 0) bits.push(c.waiting + " waiting on you")
                  if ((c.active || 0) > 0) bits.push(c.active + " active")
                  if (root.unreadBots > 0) bits.push(root.unreadBots + " unread")
                  if ((c.no_chat || 0) > 0) bits.push(c.no_chat + " without a chat")
                  return bits.join(" · ")
                }
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.faint }

          // ---- rows
          Repeater {
            id: repeater
            model: root.rows

            Item {
              id: rowItem
              required property var modelData
              required property int index
              width: column.width
              height: modelData.kind === "section" || modelData.kind === "pinnedHeader" ? Style.space(26)
                    : modelData.kind === "pinnedAgent" ? Style.space(20)
                    : modelData.kind === "attach" || modelData.kind === "pinned" ? Style.space(26)
                    : modelData.kind === "rule" ? Style.space(13) : Style.space(46)

              // The break between "wants you" and everyone else. At the same
              // weight as the section rules it was too quiet to do its job -
              // this is the one division in the list that carries meaning.
              Rectangle {
                visible: modelData.kind === "rule"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: root.divider
              }

              // Bots with news get greeted when the panel opens.
              readonly property bool wantsGreeting: modelData.kind === "bot"
                && (!!modelData.bot.chat && modelData.bot.chat.unread || modelData.bot.waiting)

              Connections {
                target: root
                function onGreetRequested(everyone) {
                  if (rowItem.modelData.kind !== "bot") return
                  if (everyone || rowItem.wantsGreeting) rowGreet.restart()
                }
              }
              // Staggered by position so the flourishes read as a wave.
              Timer {
                id: rowGreet
                interval: 60 + rowItem.index * 85
                onTriggered: if (rowAvatar) rowAvatar.play(root.nextFlourish())
              }

              // section header
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "section"
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                text: root.label(modelData.name).toUpperCase() + "  " + (modelData.count || "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // The session rows: the one hanging off a bot, and its pinned chats.
              // Both are ordinary visible sessions, so both take the cursor and a
              // click - they open that session, not the bot.
              Rectangle {
                visible: modelData.kind === "attach" || modelData.kind === "pinned"
                anchors.fill: parent
                anchors.leftMargin: -Style.space(4)
                anchors.rightMargin: -Style.space(4)
                radius: Style.space(1.5)
                color: index === root.cursor ? root.hilite : "transparent"

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursor = index
                    var e = mapToItem(keyCatcher, mouseX, mouseY)
                    keyCatcher.pointerAt(e.x, e.y)
                  }
                  onExited: keyCatcher.pointerGone()
                  onClicked: root.clickRow(index)
                  onPositionChanged: function(mouse) {
                    var p = mapToItem(keyCatcher, mouse.x, mouse.y)
                    keyCatcher.pointerAt(p.x, p.y)
                  }
                }
              }

              // Under the bot's own text column, so the session reads as belonging
              // to the row above it. A live session takes the accent colour and a
              // marker; a finished one stays quiet.
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "attach" || modelData.kind === "pinned"
                anchors.left: parent.left
                anchors.leftMargin: Style.space(37)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(37) - Style.space(46)
                text: {
                  // Only the two session row kinds own a session. A bot, section or
                  // rule row has none, and this binding runs for every row - an
                  // invisible item still evaluates its bindings - so answering ""
                  // here is what keeps the list from throwing on each rebuild.
                  if (modelData.kind === "attach") {
                    return root.label((modelData.mode === "live" ? "\u25b8 " : "\u21b3 ")
                                      + String((modelData.session || {}).title || ""))
                  }
                  if (modelData.kind === "pinned") {
                    return root.label(String((modelData.session || {}).title || ""))
                  }
                  return ""
                }
                color: modelData.kind === "attach" && modelData.mode === "live" ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
              }
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "attach" || modelData.kind === "pinned"
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtAgo(modelData.session ? modelData.session.last_activity_at : 0)
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // The pinned section, and the bot each group of pinned chats belongs
              // to - the desktop's own Pinned, split by who owns the chat.
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "pinnedHeader"
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                text: "PINNED"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "pinnedAgent"
                anchors.left: parent.left
                anchors.leftMargin: Style.space(9)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)
                text: root.label(String(modelData.bot.title || modelData.bot.name || "")).toUpperCase()
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // bot row
              Rectangle {
                visible: modelData.kind === "bot"
                anchors.fill: parent
                anchors.leftMargin: -Style.space(4)
                anchors.rightMargin: -Style.space(4)
                radius: Style.space(1.5)
                color: index === root.cursor ? root.hilite : "transparent"

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(9)

                  Avatar {
                    id: rowAvatar
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(28)
                    height: Style.space(28)
                    shape: modelData.kind === "bot" ? modelData.bot.shape : "blob"
                    image: modelData.kind === "bot" && modelData.bot.image
                           ? "file://" + modelData.bot.image : ""
                    fill: modelData.kind === "bot" ? root.colorFor(modelData.bot) : root.dim
                    eyeColor: root.eyeInk
                    face: modelData.kind === "bot" ? root.faceFor(modelData.bot) : "neutral"
                    Component.onCompleted: root.flourishCount = flourishCount

                    // Watch the pointer while it is over the panel. Every row
                    // maps the one shared position into its own coordinates, so
                    // the whole list looks at the same spot from where it sits.
                    readonly property point look: mapFromItem(keyCatcher,
                      keyCatcher.pointerX, keyCatcher.pointerY)
                    looking: keyCatcher.pointerX >= 0
                    followX: look.x
                    followY: look.y

                    // Just read, or just answered: take a bow.
                    property bool wasWanted: false
                    onFaceChanged: {
                      var wants = face === "attentive" || face === "excited" || face === "curious"
                      if (wants) wasWanted = true
                      else if (wasWanted) { wasWanted = false; celebrate() }
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(28) - Style.space(9) - badge.width - Style.space(9)
                    spacing: Style.space(1)

                    Row {
                      spacing: Style.space(5)
                      width: parent.width
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot"
                          ? root.label(modelData.bot.title || modelData.bot.name) : ""
                        color: modelData.kind === "bot" && modelData.bot.waiting ? root.urgent : root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: modelData.kind === "bot"
                          && (modelData.bot.waiting || (modelData.bot.chat && modelData.bot.chat.unread))
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot" ? root.label(modelData.bot.handle || "") : ""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: Math.max(0, parent.width - Style.space(120))
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: modelData.kind === "bot" ? root.label(root.rowPreview(modelData.bot)) : ""
                      // Full foreground for the ones waiting on you, dimmed for
                      // the rest: weight carries it, so nothing has to shout.
                      color: modelData.kind === "bot" && modelData.bot.waiting ? root.fg
                             : (modelData.kind === "bot" && modelData.bot.active ? root.accent : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  Column {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(38)
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      text: modelData.kind === "bot" ? root.fmtAgo(root.lastActivity(modelData.bot)) : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      anchors.right: parent.right
                      visible: modelData.kind === "bot" && !!modelData.bot.chat && modelData.bot.chat.unread
                      width: Math.max(Style.space(14), unreadText.implicitWidth + Style.space(6))
                      height: Style.space(14)
                      radius: height / 2
                      color: root.accent
                      Text {
                        textFormat: Text.PlainText
                        id: unreadText
                        anchors.centerIn: parent
                        text: modelData.kind === "bot" ? "\u2022" : ""
                        color: Color.background
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursor = index
                    var e = mapToItem(keyCatcher, mouseX, mouseY)
                    keyCatcher.pointerAt(e.x, e.y)
                  }
                  onExited: keyCatcher.pointerGone()
                  onClicked: root.clickRow(index)
                  // Hover goes to the topmost item, so a row would otherwise
                  // starve the panel-wide tracker and the eyes would freeze
                  // exactly when you are looking at them.
                  onPositionChanged: function(mouse) {
                    var p = mapToItem(keyCatcher, mouse.x, mouse.y)
                    keyCatcher.pointerAt(p.x, p.y)
                  }
                }
              }
            }
          }

          // ---- empty states
          Text {
            textFormat: Text.PlainText
            visible: root.snap && root.bots.length === 0
            width: parent.width
            topPadding: Style.space(10)
            text: "no bots in this Hermes install yet"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle { width: parent.width; height: 1; color: root.faint; visible: root.bots.length > 0 }


          // ---- footer
          Item {
            id: footer
            width: parent.width
            height: Style.space(30)
            // The hint has to fit the narrowest card the panel can be, in every
            // theme font size, so it steps down through three wordings and only
            // then elides. One fixed wording runs past the card edge.
            readonly property string hintFull: "j/k move · ⏎ open · g " + root.ordering
                                               + " · p pinned · s " + root.source + " · h hide · r beside mark: " + root.barMetric
            readonly property string hintMedium: "j/k · ⏎ open · g " + root.ordering
                                                 + " · p pinned · s " + root.source + " · h hide · r mark: " + root.barMetric
            readonly property string hintShort: "j/k · ⏎ open · g " + root.ordering
                                                + " · p · s · h hide · r " + root.barMetric
            TextMetrics {
              id: hintFullMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: footer.hintFull
            }
            TextMetrics {
              id: hintMediumMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: footer.hintMedium
            }
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              elide: Text.ElideRight
              text: hintFullMetrics.advanceWidth <= width ? footer.hintFull
                    : (hintMediumMetrics.advanceWidth <= width ? footer.hintMedium : footer.hintShort)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}

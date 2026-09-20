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
// something unread or has spoken recently, excited while it is active. Keys: j/k move ·
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
  readonly property string sender: Qt.resolvedUrl("bin/hermbot-send").toString().replace(/^file:\/\//, "")

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

  // ---- the chat window ------------------------------------------------------
  // A row opens its conversation here instead of handing it to the desktop, so
  // the bar can be the whole surface. `chat` is the thread being read (null = the
  // roster is showing); the turns, the live tail and the pending flag are separate
  // properties so a streaming reply can be appended without rebuilding history.
  property var chat: null
  property var chatTurns: []
  property string chatLive: ""
  property bool chatPending: false
  property string chatError: ""
  property bool chatLoading: false
  // Which instance the open chat belongs to. Captured when it opens: the source
  // can be switched while a window is up, and the thread must keep being read and
  // written on the machine it was opened from.
  property string chatSource: "auto"
  // Files queued for the next turn: { path, name, image }
  property var chatAttach: []

  // The in-panel file browser: whether it is open, where it is, and what is there.
  property bool pickerOpen: false
  property string pickerDir: ""
  property string pickerParent: ""
  property var pickerEntries: []
  property string pickerError: ""

  // Whether the transcript also shows HOW the bot got there - its thinking, every
  // call it made, what came back. On by default because watching the work is the
  // point of having the window; `w` turns it off for a plain conversation.
  property bool showWork: String(setting("showWork", "true")) !== "false"
  // `n` starts a chat with the bot under the cursor, so the footer has to name that
  // bot - otherwise the key silently opens a conversation with somebody the panel
  // never mentioned. Empty when the cursor is not on a bot.
  readonly property string newBot: {
    var row = (cursor >= 0 && cursor < rows.length) ? rows[cursor] : null
    var bot = (row && (row.kind === "bot" || row.kind === "attach" || row.kind === "pinned"))
              ? row.bot : null
    return bot ? ("@" + bot.name) : ""
  }
  // What the bot is doing right now, before the turn lands in the store.
  property var chatLiveWork: []
  // Which work rows have been opened out. Keyed by position in the transcript.
  property var workExpanded: ({})

  // ---- keeping the window live ----------------------------------------------
  // A one-shot reload after a send is a promise the window has to keep; if it does
  // not fire, the conversation freezes and only leaving and re-entering fixes it.
  // So the window does not rely on it: every roster tick checks the open session's
  // message count and re-reads it when it moved. That covers a reply arriving from
  // ANY surface - this window, the desktop, a cron delivery - within one poll.
  property int chatRenderedCount: -1
  property bool chatSeenInSnap: false
  property bool chatRereadPending: false
  // The message count when the current send started: what tells a landed reply
  // apart from the turn that was already there.
  property int chatSendCount: -1
  // Which surface holds a writer's lease on the open conversation, '' when free.
  // Hermes allows exactly one writer per session, so this is not advisory.
  property string chatHeld: ""
  // Counts completed transcript reads. A probe has no way to watch a timer, and the
  // claim "the queue keeps asking" is only worth anything if it can be counted.
  property int chatReads: 0
  property int chatRebuilds: 0
  // How many times the live tail was emptied while a turn was STILL running. The flicker
  // this window had looked exactly like that - words on screen, gone, back again - and it
  // happens between two probe reads, so it has to be counted as it occurs rather than
  // sampled. It must stay at zero: a clear mid-turn is the bug.
  property int chatLiveClears: 0
  property int chatLiveSeen: 0
  // Messages typed while the chat is busy or leased elsewhere. Hermes allows one
  // writer, so a send in that window would be refused outright - but refusing the
  // TYPING is worse: it makes you sit and wait for someone else's turn to end before
  // you can even write the sentence. So the box always takes what you give it, and
  // the queue hands the message over the moment the chat is free again.
  property var chatQueue: []
  // The composer grows with what you put in it. Dictation and pasted text arrive as
  // several lines, and a one-line box shows you only the tail of them - which is
  // unreadable exactly when the text is worth reading twice. The log gives up the
  // height the box takes, so the window itself stays the size it was.
  readonly property real chatBoxMin: Style.space(52)
  readonly property real chatBoxMax: Style.space(260)
  // The chat window is resizable by dragging its edges. The panel re-centres itself
  // horizontally on every width change (cardOrigin puts x at screenW/2 - contentWidth/2),
  // so a drag on ONE side grows BOTH sides: the window scales around its centre instead
  // of sliding to one side. Height is a different matter - the card is pinned under the
  // bar (y = barH + gap), so it can only grow downward. There is nothing above the bar
  // to grow into, and that is upstream geometry, not a choice made here.
  property real chatWidth: Style.space(820)
  property real chatLogBase: Style.space(620)
  // While a width drag is in flight this holds the transcript's wrap width, and the
  // transcript keeps it instead of following the window. Re-wrapping is what made the
  // drag stutter: every mouse move resized the card, and the card resized ~415 turns of
  // text, each one re-flowing its lines. Freezing the wrap width takes that work off the
  // drag entirely; the text re-flows once, on release. 0 means "not dragging".
  property real dragWrap: 0
  // The composer's height follows the width too: a narrower window wraps the draft into
  // more lines, the box grows, and the log shrinks to pay for it. During a drag that
  // reads as the whole window jumping while you are only pulling one edge. Hold the box
  // at the height it had when the drag started, and let it settle on release.
  property real dragBox: 0
  function beginDrag() {
    root.dragWrap = turns.width
    root.dragBox = root.chatBoxHeight
  }
  function endDrag() {
    root.dragWrap = 0
    root.dragBox = 0
  }
  // A drag that never gets its release - a stray click, a pointer the compositor took
  // away - would leave the transcript frozen at a stale width and silently stop it
  // wrapping. Any change of conversation ends the drag state.
  onChatLiveChanged: {
    if (root.chatPending && root.chatLive === "" && root.chatLiveSeen > 0)
      root.chatLiveClears = root.chatLiveClears + 1
    if (root.chatLive !== "") root.chatLiveSeen = root.chatLive.length
  }
  onChatChanged: root.endDrag()
  // Text size, on Ctrl+= / Ctrl+- (Ctrl+0 puts it back). The chat uses exactly two
  // sizes, so one multiplier over them is enough. Everything inside the panel scales -
  // the conversation, the roster, the footer hints - because it is all one window and
  // one setting is easier to reason about than three. The bar widget's own label keeps
  // the theme's size: it lives in the bar, not in this window, and growing it would
  // push the bar around for a setting about reading.
  property real fontScale: 1.0
  readonly property real fontMin: 0.75
  readonly property real fontMax: 1.8
  readonly property real fontStep: 0.1
  function fs(px) {
    return Math.round(px * root.fontScale)
  }
  function bumpFont(delta) {
    var next = Math.round((root.fontScale + delta) * 100) / 100
    root.fontScale = Math.max(root.fontMin, Math.min(root.fontMax, next))
  }
  function resetFont() {
    root.fontScale = 1.0
  }
  readonly property real chatMinWidth: Style.space(420)
  readonly property real chatMaxWidth: Style.space(1400)
  readonly property real chatMinLog: Style.space(170)
  readonly property real chatMaxLog: Style.space(740)
  function clampChatWidth(v) {
    return Math.max(root.chatMinWidth, Math.min(root.chatMaxWidth, v))
  }
  function clampChatLog(v) {
    return Math.max(root.chatMinLog, Math.min(root.chatMaxLog, v))
  }
  // The field's own height. A TextArea draws its text INSIDE its own padding, so a
  // height equal to contentHeight leaves it only contentHeight - top - bottom of room
  // and the last line disappears under the bottom edge. The padding has to be added,
  // not assumed. Capped so a very long paste scrolls instead of filling the screen.
  readonly property real chatInputHeight: Math.max(Style.space(26),
                                            Math.min(root.chatBoxMax - Style.space(26),
                                                     chatInput.contentHeight
                                                     + chatInput.topPadding
                                                     + chatInput.bottomPadding))
  readonly property real chatBoxHeight: root.dragBox > 0 ? root.dragBox
                                    : Math.max(root.chatBoxMin,
                                               Math.min(root.chatBoxMax,
                                                        root.chatInputHeight + Style.space(26)))
  readonly property real chatLogHeight: Math.max(Style.space(170),
                                          (root.pickerOpen ? root.chatLogBase - Style.space(280)
                                                           : root.chatLogBase)
                                          - (root.chatBoxHeight - root.chatBoxMin))
  // A read takes a moment, and the window can move on inside it. Every open bumps
  // the epoch; a reply stamped with an older one is a reply about a conversation
  // nobody is looking at any more, and applying it is how a stale transcript
  // flashes into a window that already moved on.
  property int chatEpoch: 0
  property int threadEpoch: -1

  // Start a conversation that belongs to nobody else. Hermes has no "make an empty
  // chat" command - a chat is born from its first message - so the name is picked
  // here and the id comes back on the stream once the chat exists. The name is
  // deliberately dull and unique: it is what the desktop's sidebar will show.
  function startNewChat(bot) {
    if (!bot) return
    var now = new Date()
    // Seconds, not minutes: a chat is created by NAME, and --create-if-missing
    // RESUMES a session whose name already exists. Two names that collide in the
    // same minute would silently continue the previous chat instead of starting one.
    var title = "Hermbot " + ("0" + now.getHours()).slice(-2) + ":"
                + ("0" + now.getMinutes()).slice(-2) + ":"
                + ("0" + now.getSeconds()).slice(-2)
    chatEpoch += 1
    threadEpoch = -1
    chat = { bot: String(bot.name), title: title, session_id: "", isNew: true }
    chatTurns = []
    chatLive = ""
    chatLiveWork = []
    chatError = ""
    chatPending = false
    chatLoading = false
    chatHeld = ""
    chatRenderedCount = -1
    chatSeenInSnap = false
    chatRereadPending = false
    chatSendCount = -1
    chatSource = root.source
    chatFocus.restart()
  }

  function startNewChatForCursor() {
    var row = (cursor >= 0 && cursor < rows.length) ? rows[cursor] : null
    var bot = (row && (row.kind === "bot" || row.kind === "attach" || row.kind === "pinned"))
              ? row.bot : null
    // A heading is not a bot: walk up to the nearest row that is one, and only then
    // fall back to the top of the list. `n` must never be a silent no-op - and
    // whatever it picks, the chat window names it.
    if (!bot) {
      for (var i = Math.min(cursor, rows.length - 1); i >= 0; i--) {
        var r = rows[i]
        if (r.kind === "bot" || r.kind === "attach" || r.kind === "pinned") { bot = r.bot; break }
      }
    }
    if (!bot && bots.length > 0) bot = bots[0]
    if (bot) root.startNewChat(bot)
  }

  // What the chat window is showing, as one line. Lives on the widget (not in the
  // IPC handler) because the handlers call it too. Always JSON, and it carries the
  // panel's own state first: a screenshot run has to prove the panel is actually up
  // before it grabs, and `geometry` answers with the last card it knew about whether
  // or not anything is on screen.
  function chatStateText() {
    var st = { panel: root.opened ? "open" : "closed",
               roster: root.demoMode ? "demo" : "live" }
    if (root.chat === null) return JSON.stringify(st)
    st.bot = root.chat.bot
    st.title = root.chat.title
    st.session_id = root.chat.session_id
    st.isNew = root.chat.isNew === true
    st.held = root.chatHeld
    st.turns = root.chatTurns.length
    st.pending = root.chatPending
    st.queued = root.chatQueue.length
    st.reads = root.chatReads
    st.live = root.chatLive.length
    st.rebuilds = root.chatRebuilds
    st.clears = root.chatLiveClears
    st.box = Math.round(root.chatBoxHeight)
    st.cursor = root.cursor
    return JSON.stringify(st)
  }

  // The bot's own Bot Chat is the one conversation this window can always own: the
  // desktop keeps it out of its sidebar, so nothing else holds it.
  function botByName(name) {
    for (var i = 0; i < bots.length; i++)
      if (String(bots[i].name) === String(name)) return bots[i]
    return null
  }

  function botChatOf(name) {
    var bot = root.botByName(name)
    return bot ? (bot.chat || null) : null
  }

  function canSwitchToBotChat() {
    if (!root.chat) return false
    var own = root.botChatOf(root.chat.bot)
    return !!(own && own.session_id && String(own.session_id) !== String(root.chat.session_id))
  }

  function switchToBotChat() {
    if (!root.chat || !root.canSwitchToBotChat()) return
    var bot = root.botByName(root.chat.bot)
    if (bot) root.openChat(bot, bot.chat)
  }

  function sessionCountIn(snap, sessionId) {
    if (!snap || !snap.bots) return -1
    for (var i = 0; i < snap.bots.length; i++) {
      var b = snap.bots[i]
      var a = b.attach
      if (a && String(a.session_id) === sessionId) return Number(a.message_count || 0)
      var pins = b.pinned || []
      for (var j = 0; j < pins.length; j++)
        if (String(pins[j].session_id) === sessionId) return Number(pins[j].message_count || 0)
    }
    return -1
  }

  function chatTick() {
    if (root.chat === null) return
    var count = root.sessionCountIn(root.snap, String(root.chat.session_id))
    if (count < 0) { root.chatSeenInSnap = false; return }
    root.chatSeenInSnap = true
    if (count !== root.chatRenderedCount) root.reloadChat()
  }

  // Nothing may stall silently: if the roster stops carrying this session at all
  // (its row moved on to a newer chat), ask for the thread directly instead.
  Timer {
    id: chatSafety
    interval: 5000
    repeat: true
    running: root.chat !== null
    onTriggered: if (!root.chatSeenInSnap) root.reloadChat()
  }

  // The drain must never wait on a coincidence. flushQueue runs when a read completes,
  // and a read only starts when the session's message count changes - but the lease
  // freeing changes no count, so a queued message sat there until some unrelated refresh
  // happened to come along. Toggling "stream" was such a refresh (toggleWork reloads),
  // which is why that felt like the fix. While anything is queued, keep asking: the read
  // that follows sees held as empty and flushQueue sends the message straight away.
  Timer {
    id: queuePump
    interval: 1200
    repeat: true
    running: root.chatQueue.length > 0 && root.chat !== null
    onTriggered: root.reloadChat()
  }

  // A lease changes without the store saying anything: Hermes refuses a second writer
  // while the holder runs and hands the chat over the moment it exits, and neither event
  // moves the message count - which is the one thing chatTick watches. A window read
  // while the chat was held would therefore keep saying "held by cli", keep the header
  // red, and keep every message queueing long after the holder was gone. So while the
  // chat is held, ask: the read that comes back empty frees the box and lets the queue
  // drain. The holder is another process, so nothing here can be told about its exit.
  Timer {
    id: leasePump
    interval: 2000
    repeat: true
    running: root.chatHeld !== "" && root.chat !== null
    onTriggered: root.reloadChat()
  }

  function toggleWorkRow(index) {
    var next = {}
    for (var k in workExpanded) next[k] = workExpanded[k]
    next[index] = !next[index]
    workExpanded = next
  }

  // ---- transcript helpers ---------------------------------------------------
  function escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }

  // Escape, then mark up. The patterns run on already-escaped text, so nothing in a
  // message can turn into a tag of its own. `**bold**` and `code` are the two markers
  // the agent's replies actually carry, and leaving them raw is what put asterisks and
  // backticks in the middle of otherwise ordinary sentences.
  function mdEscape(s) {
    var out = root.escapeHtml(s)
    out = out.replace(/`([^`\n]+)`/g, function(_, c) {
      return '<span style="color:' + String(root.accent) + '">' + c + "</span>"
    })
    return out.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
  }

  // Links become clickable without ever letting message text turn into markup: the
  // text is escaped first and only the URLs found here are wrapped. Trailing
  // punctuation stays outside the anchor, so a link is not broken by a full stop.
  function richText(s) {
    var text = String(s)
    var re = /https?:\/\/[^\s<>()"']+/g
    var out = "", last = 0, m
    while ((m = re.exec(text)) !== null) {
      var url = m[0], trail = ""
      while (url.length > 1 && ".,;:!?".indexOf(url.charAt(url.length - 1)) >= 0) {
        trail = url.charAt(url.length - 1) + trail
        url = url.slice(0, -1)
      }
      out += root.mdEscape(text.slice(last, m.index))
      out += '<a href="' + root.escapeHtml(url) + '">' + root.escapeHtml(url) + "</a>"
      out += root.mdEscape(trail)
      last = m.index + m[0].length
    }
    return (out + root.mdEscape(text.slice(last))).replace(/\n/g, "<br/>")
  }

  function openLink(url) {
    var u = String(url || "")
    if (u.indexOf("http://") === 0 || u.indexOf("https://") === 0)
      Quickshell.execDetached(["xdg-open", u])
  }

  // A stored turn can carry `@image:<path>` - that is how the desktop hands an
  // attachment over, and what a screenshot looks like once it is in the store.
  // Text cannot draw an image, so the transcript pulls the refs out and draws them
  // above the words. `[screenshot]` is a display marker that carries no path.
  // Only an absolute path ending in an image suffix is worth drawing. Message text talks
  // about these markers - the window's own replies quote them when explaining the
  // feature - and a bare "/path" or "<suffix>" is prose, not a file. A failed Image
  // retries, and a screenful of retries is what pegged the shell at 80% CPU and made the
  // whole window feel heavy.
  function looksLikeImage(p) {
    var s = String(p || "").trim()
    if (s.charAt(0) !== "/") return false
    return root.isImagePath(s)
  }

  // A collapsed work row draws four lines. Laying out ninety thousand characters to show
  // four of them is waste, and this conversation has single messages that long. An
  // expanded row still gets the whole text - that is what expanding it is for.
  readonly property int workShownChars: 4000
  function workShown(text, i) {
    var s = String(text || "")
    if (root.workExpanded[i] || s.length <= root.workShownChars) return s
    return s.slice(0, root.workShownChars)
  }

  function imagePathsIn(text, role) {
    var out = [], m
    var s = String(text)
    var re = /@image:(\S+)/g
    while ((m = re.exec(s)) !== null)
      if (root.looksLikeImage(m[1])) out.push(m[1])
    // The bracketed form is written by Hermes for an attachment YOU sent, and only for
    // that. A bot turn that merely mentions the marker - explaining the feature, as this
    // window's own replies do - is prose. Drawing it meant a load that fails, retries,
    // and is rebuilt by every read: the shell sat at 80-90% CPU.
    if (String(role || "") !== "user") return out
    var re2 = /\[Image attached at:\s*([^\]]+?)\s*\]/g
    while ((m = re2.exec(s)) !== null)
      if (root.looksLikeImage(m[1])) out.push(m[1])
    return out
  }

  // Strip only what was actually drawn as a picture. A message that merely mentions the
  // marker - the window's own replies do, when explaining the feature - keeps its words:
  // removing text that produced no image is how prose about the format disappeared.
  function textWithoutImages(text, role) {
    var s = String(text)
    s = s.replace(/@image:\S+/g, function(m) {
      return root.looksLikeImage(m.slice(7)) ? "" : m
    })
    if (String(role || "") === "user")
      s = s.replace(/\[Image attached at:[^\]]*\]/g, function(m) {
        var inner = m.replace(/^\[Image attached at:\s*/, "").replace(/\]$/, "")
        return root.looksLikeImage(inner) ? "" : m
      })
    return s.replace(/\[screenshot\]/g, "").trim()
  }

  function clockOf(ts) {
    if (!ts) return ""
    var d = new Date(Number(ts) * 1000)
    return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
  }

  // ---- attachments ----------------------------------------------------------
  readonly property var imageSuffixes: [".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"]

  function isImagePath(p) {
    var s = String(p).toLowerCase()
    for (var i = 0; i < root.imageSuffixes.length; i++)
      if (s.slice(-root.imageSuffixes[i].length) === root.imageSuffixes[i]) return true
    return false
  }

  function baseName(p) {
    var s = String(p)
    var cut = s.lastIndexOf("/")
    return cut >= 0 ? s.slice(cut + 1) : s
  }

  function attachFile(p) {
    var path = String(p || "").replace(/^file:\/\//, "")
    if (path === "") return
    for (var i = 0; i < chatAttach.length; i++)
      if (chatAttach[i].path === path) return
    chatAttach = chatAttach.concat([{ path: path, name: root.baseName(path),
                                      image: root.isImagePath(path) }])
    chatFocus.restart()
  }

  function detachFile(index) {
    var out = []
    for (var i = 0; i < chatAttach.length; i++) if (i !== index) out.push(chatAttach[i])
    chatAttach = out
  }

  function clearAttach() { chatAttach = [] }

  // ---- the file browser -----------------------------------------------------
  // In-panel on purpose. The panel is a full-screen surface on WlrLayer.Overlay, so
  // a separate chooser can only ever appear UNDERNEATH it - and the platform dialog
  // on this machine is the GTK one that looks like Nautilus. Browsing here keeps
  // everything above the chat, never loses focus, and reads as the same widget.
  function openPicker() {
    pickerOpen = true
    // Hand the keys back to the panel for as long as the browser is up. Without this
    // the box keeps the focus it already had, the catcher stays blocked, and Esc goes
    // to a control that has no idea the browser exists.
    keyCatcher.forceActiveFocus()
    root.browseTo("")
  }

  function closePicker() {
    pickerOpen = false
    pickerEntries = []
    pickerError = ""
    chatFocus.restart()
  }

  function browseTo(dir) {
    pickerError = ""
    pickerEntries = []
    lsProc.command = [root.watcher, "--ls", String(dir || ""), "--limit", "400",
                      "--source", chatSource]
    lsProc.running = true
  }

  function pickEntry(entry) {
    if (!entry) return
    if (entry.dir) { root.browseTo(entry.path); return }
    root.attachFile(entry.path)
    root.closePicker()
  }

  function humanSize(bytes) {
    var n = Number(bytes || 0)
    if (n < 1024) return n + " B"
    if (n < 1048576) return Math.round(n / 1024) + " K"
    if (n < 1073741824) return (n / 1048576).toFixed(1) + " M"
    return (n / 1073741824).toFixed(1) + " G"
  }

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
  // The staged conversation the chat window shows in demo mode. Ages are relative to
  // when demo mode was switched on, so the clocks stay believable.
  readonly property var demoThread: {
    var t = (demoStart || Date.now()) / 1000
    var ago = function(mins) { return t - mins * 60 }
    return [
      { role: "user", ts: ago(6),
        text: "Run the watcher twice at the same instant and tell me whether the lock holds." },
      { role: "think", ts: ago(6),
        text: "Two processes, one lock file. Start both, then compare exit codes and how long the second one waited." },
      { role: "call", ts: ago(5), text: "terminal · ls -la ~/.local/state/omarchy/hermbot/" },
      { role: "result", ts: ago(5),
        text: "terminal · total 12\n-rw-r--r-- 1 ozz1ee ozz1ee 412 seen.json\n-rw-r--r-- 1 ozz1ee ozz1ee   0 watcher.lock" },
      { role: "call", ts: ago(4),
        text: "terminal · python3 -c \"start two watchers at once, time both to exit\"" },
      { role: "result", ts: ago(4),
        text: "terminal · first exit 0 in 0.03s, second exit 0 in 0.44s - the second waited for the lock" },
      { role: "think", ts: ago(3),
        text: "Both exited cleanly and the second blocked for four tenths of a second. The race is closed." },
      { role: "bot", ts: ago(2),
        text: "The race is real, and it is closed. Two watchers started at the same instant:\n\n- the first took the lock and finished in 0.03s\n- the second waited 0.44s, then read the state the first had written\n\nNo double write, and the state file ends on a single consistent snapshot." }
    ]
  }
  readonly property var demoSnap: {
    var t = (demoStart || Date.now()) / 1000
    var ago = function(mins) { return t - mins * 60 }
    var bot = function(name, title, shape, color, unread, waiting, active, mins, text, fromBot) {
      return { name: name, handle: "@" + name, title: title, description: "",
               shape: shape, color: color, image_kind: "shape", custom: true, created: null,
               gateway_served: true, waiting: waiting, unread_count: unread,
               active: active, activity_at: ago(mins),
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
  // is what dozes.
  readonly property double staleAfterS: 7 * 24 * 3600
  function faceFor(b) {
    var chat = b.chat || ({})
    // Same pose Rakabot gives its unread bots. One level, not Rakabot's two: the
    // count it splits on (`unread > 1` -> excited, exactly one -> curious) has no
    // reliable source here. The desktop's own message-count watermark sits in a
    // Snappy-compressed LevelDB block and reads back with truncated session ids,
    // so that split would be decided on garbage - refusing it is the honest call.
    if (b.waiting) return "excited"
    // The desktop's own 90-second activity window, kept as the one deliberate
    // addition: a bot mid-turn is awake before its answer lands and moves the
    // count. Rakabot reads a live unread counter and needs no such window.
    if (b.active) return "curious"
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

  // ------------------------------------------------------------------- chat io
  // Reading one conversation, and delivering a message into it. Both go through
  // the same scripts the roster uses, so a remote source behaves the same way -
  // and the text never touches a shell: it reaches hermbot-send as argv, and from
  // there the agent reads it out of a file.
  Process {
    id: threadProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var d
        try { d = JSON.parse(String(line)) } catch (e) { return }
        if (!d || d.kind !== "thread") return
        // The window moved on while this read was in flight: its answer describes a
        // conversation nobody is looking at, and applying it is exactly what made a
        // stale transcript flash into a freshly opened chat.
        if (root.threadEpoch !== root.chatEpoch) return
        var out = []
        // In demo mode the chat is staged too. The demo roster carries session ids no
        // store knows, so reading one returns nothing and a screenshot of the chat
        // window would be a screenshot of an empty window. This is the shape a real
        // turn has: a question, the work, the answer.
        if (root.demoMode) out = root.demoThread
        else {
        var turns = d.turns || []
        for (var i = 0; i < turns.length; i++)
          out.push({ role: String(turns[i].role), text: String(turns[i].text),
                     ts: turns[i].ts || 0 })
        }
        if (!root.sameTurns(out)) {
          root.chatTurns = out
          root.chatRebuilds = root.chatRebuilds + 1
        }
        root.chatRenderedCount = Number(d.message_count || 0)
        // Who holds the write lease. Re-read on every tick, so the window knows the
        // moment the desktop opens or releases the chat.
        root.chatHeld = String(d.held || "")
        var last = out.length > 0 ? String(out[out.length - 1].role) : ""
        // A bot turn in the store means the turn is over, whatever the send process
        // reports. Without this the window can stay locked on a process that never
        // announces its exit - and then you cannot even send a second message.
        var landed = last === "bot" && root.chatSendCount >= 0
                     && root.chatRenderedCount > root.chatSendCount
        if (landed) {
          root.chatPending = false
          root.chatSendCount = -1
        }
        // The courtesy tail is only worth keeping while the reply is not in the
        // store yet; otherwise the reload would print the same answer twice.
        if (!root.chatPending || landed) {
          root.chatLive = ""
          root.chatLiveWork = []
        }
        root.chatLoading = false
        // A demo session is in no store, so the read reports that it cannot be found.
        // True, and useless here: the window is showing a staged transcript and the
        // message would sit under the input box in every demo screenshot.
        if (d.error && !root.demoMode) root.chatError = String(d.error)
        if (root.chat && d.bot)
          root.chat = { bot: String(d.bot),
                        title: String(d.title || root.chat.title),
                        session_id: root.chat.session_id,
                        isNew: root.chat.isNew === true }
        // The lease is re-read on every tick, so this is where a queued message gets
        // its chance: the moment the chat is free, it goes out without you touching
        // anything.
        root.flushQueue()
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        var s = String(data).trim()
        if (s !== "") console.warn("hermbot chat", s)
      }
    }
    onExited: function(code) {
      root.chatLoading = false
      root.chatReads += 1
      // A tick that arrived mid-read asked for another one.
      if (root.chatRereadPending) root.reloadChat()
    }
  }

  Process {
    id: sendProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var d
        try { d = JSON.parse(String(line)) } catch (e) { return }
        if (!d) return
        if (d.type === "text" && d.text) {
          root.chatLive = root.chatLive + String(d.text)
        } else if (d.type === "tool_use") {
          // The bot is reaching for something. Showing it the moment it happens is
          // the whole reason the stream carries these events.
          root.chatLiveWork = root.chatLiveWork.concat([
            { role: "call", text: root.callLine(String(d.name || "tool"), d.input) }])
        } else if (d.type === "tool_result") {
          root.chatLiveWork = root.chatLiveWork.concat([
            { role: "result", text: root.resultLine(String(d.name || "tool"), d.output) }])
        } else if (d.type === "hermbot" && d.session_id) {
          // Our own line, after the agent's stream: the chat this turn created now
          // exists, so the window adopts its id and can read it back from here on.
          if (root.chat) {
            root.chat = { bot: root.chat.bot,
                          title: String(d.title || root.chat.title),
                          session_id: String(d.session_id), isNew: false }
            root.chatRenderedCount = -1
            root.reloadChat()
          }
        } else if (d.type === "result" && d.exit_code !== undefined && d.exit_code !== 0) {
          root.chatError = "the turn failed (exit " + d.exit_code + ")"
        }
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        var s = String(data).trim()
        if (s === "") return
        // The machine-readable reason line the CLI adds for one-shot subprocesses.
        if (s.indexOf("hermes-refusal-reason:") === 0) return
        // The one refusal worth translating. Hermes allows a single writer per
        // session on purpose - two surfaces on one conversation corrupt it - so this
        // is not a bug to paper over, it is a door that is shut.
        if (s.indexOf("open in another Hermes") >= 0) {
          root.chatError = "This chat is open in Hermes Desktop right now, and Hermes "
                         + "allows one writer per chat. Close it there, or pick the bot "
                         + "itself from the roster to talk in its own Bot Chat."
          return
        }
        // Anything else the agent said about why it failed is the most useful thing
        // this window can show, so it is surfaced rather than only logged.
        root.chatError = s
        console.warn("hermbot chat", s)
      }
    }
    onExited: function(code) {
      root.chatPending = false
      if (code !== 0 && root.chatError === "") root.chatError = "the send exited " + code
      // A beat before re-reading: the row is written as the turn completes, and
      // this is what keeps the window from flashing an empty reply.
      chatSettle.restart()
      // The turn just ended, which is the other moment the chat becomes free.
      root.flushQueue()
    }
  }

  // Focus follows the window, not the click: after sending, the box is ready again.
  // Two things must hold before the box may take the keys:
  //   - it is enabled. A disabled TextField cannot hold focus, and forceActiveFocus()
  //     on one leaves the window with NO active item at all, which silently kills
  //     every key in the panel, Esc included.
  //   - the browser is folded away. While it is open the keys belong to the panel,
  //     so Esc reaches the catcher and can close the browser instead of the chat.
  // Without both, the browser was impossible to dismiss from the keyboard: the only
  // thing listening was a box that either could not hold focus or swallowed the key.
  Timer { id: chatFocus; interval: 80
          onTriggered: if (root.chat !== null && chatInput.enabled && !root.pickerOpen)
                         chatInput.forceActiveFocus() }
  Timer { id: chatSettle; interval: 350; onTriggered: root.reloadChat() }

  // The directory listing behind the in-panel browser. One call per directory, so
  // nothing walks the filesystem in the background.
  Process {
    id: lsProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var d
        try { d = JSON.parse(String(line)) } catch (e) { return }
        if (!d || d.kind !== "ls") return
        root.pickerDir = String(d.dir || "")
        root.pickerParent = String(d.parent || "")
        root.pickerError = String(d.error || "")
        var out = []
        var es = d.entries || []
        for (var i = 0; i < es.length; i++)
          out.push({ name: String(es[i].name), path: String(es[i].path),
                     dir: !!es[i].dir, size: Number(es[i].size || 0) })
        root.pickerEntries = out
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        var s = String(data).trim()
        if (s !== "") console.warn("hermbot files", s)
      }
    }
  }
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
        // The roster's own poll is the heartbeat the chat window rides on.
        root.chatTick()
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

  // ------------------------------------------------------------------ the chat
  // Open a conversation in the panel. The thread is read from the bot's own store,
  // and whatever is typed is delivered into THAT session - not into the canonical
  // Bot Chat - so the reply lands in the conversation on screen. That is the whole
  // point of the window: the row you picked is the row you talk in.
  function openChat(bot, session) {
    if (!bot || !session) return
    var sid = String(session.session_id || "")
    if (!sid) return
    chatEpoch += 1
    threadEpoch = -1
    chat = { bot: String(bot.name),
             title: String(session.title || bot.title || bot.name),
             session_id: sid }
    chatTurns = []
    chatLive = ""
    chatError = ""
    chatPending = false
    chatLoading = true
    chatLiveWork = []
    workExpanded = ({})
    chatRenderedCount = -1
    chatSeenInSnap = false
    chatRereadPending = false
    chatSendCount = -1
    chatHeld = ""
    chatSource = root.source
    root.reloadChat()
    chatFocus.restart()
  }

  function closeChat() {
    if (sendProc.running) sendProc.running = false
    chatEpoch += 1
    threadEpoch = -1
    chat = null
    chatTurns = []
    chatLive = ""
    chatError = ""
    chatPending = false
    chatLoading = false
    chatLiveWork = []
    chatRenderedCount = -1
    chatSeenInSnap = false
    chatRereadPending = false
    chatSendCount = -1
    chatHeld = ""
    root.clearAttach()
    // The chat's input held the keys. Leaving them on an item that is now hidden is
    // how the roster ends up deaf: `n`, `r`, `p`, `s` all stop answering and the
    // panel looks broken without a single error in the log.
    keyCatcher.forceActiveFocus()
  }

  // The read behind the transcript. With the work shown the window needs many more
  // rows, because one turn can be twenty of them.
  function threadCommand() {
    var cmd = [root.watcher, "--thread", root.chat.session_id, "--source", chatSource]
    // The window draws every row it is handed, and a row costs its text layout. Four
    // hundred rows - work rows included - held the shell at 40-50% of a core while the
    // chat was open, which is what "heavy" felt like. This is several screens of
    // conversation, more than the window can show at once.
    if (root.showWork) return cmd.concat(["--limit", "80", "--work"])
    return cmd.concat(["--limit", "40"])
  }

  function toggleWork() {
    showWork = !showWork
    Quickshell.execDetached(["omarchy", "bar", "set", "ozz1ee.hermbot", "showWork",
                             showWork ? "true" : "false"])
    if (root.chat !== null) root.reloadChat()
  }

  // One line for a call the bot made, from the stream's input object or the store's
  // JSON string. Same argument keys the reader prefers, so both views read alike.
  function callLine(name, input) {
    var args = input
    if (typeof args === "string") {
      try { args = JSON.parse(args) } catch (e) { args = null }
    }
    var hint = ""
    if (args && typeof args === "object") {
      var keys = ["command", "path", "file_path", "query", "pattern", "url",
                  "prompt", "text", "name"]
      for (var i = 0; i < keys.length; i++) {
        var v = args[keys[i]]
        if (typeof v === "string" && v.trim() !== "") { hint = v; break }
      }
      if (hint === "") {
        for (var k in args) {
          if (typeof args[k] === "string" && args[k].trim() !== "") { hint = args[k]; break }
        }
      }
    }
    hint = (" " + hint).split(/\s+/).join(" ").trim()
    return String(name) + (hint !== "" ? " · " + hint.slice(0, 130) : "")
  }

  // One line for a result: the first thing it actually said, an error first.
  function resultLine(name, output) {
    var text = String(output || "")
    if (text.trim().charAt(0) === "{") {
      try {
        var p = JSON.parse(text)
        if (p && typeof p === "object")
          text = p.error ? ("error: " + p.error) : String(p.output || p.text || "")
      } catch (e) { }
    }
    var lines = text.split("\n")
    var first = ""
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trim() !== "") { first = lines[i].trim(); break }
    return String(name) + (first !== "" ? " · " + first.slice(0, 150) : "")
  }

  // How the work reads in the transcript. The reader hands over 'name · detail' for
  // a call or a result, so the two halves split cleanly into a tag and a body.
  function workLabel(role, text) {
    if (role === "think") return "thinking"
    if (role === "call") return "⚙ " + String(text).split(" · ")[0]
    if (role === "result") return "✓ " + String(text).split(" · ")[0]
    return ""
  }

  function workBody(role, text) {
    if (role !== "call" && role !== "result") return String(text)
    var cut = String(text).indexOf(" · ")
    return cut >= 0 ? String(text).slice(cut + 3) : ""
  }

  function roleLabel(role, bot) {
    if (role === "user") return "YOU"
    if (role === "bot") return "@" + bot
    return ""
  }

  function roleColor(role) {
    if (role === "user") return root.dim
    if (role === "bot") return root.accent
    if (role === "think") return root.faint
    if (role === "call") return root.dim
    return root.faint
  }

  function isWorkRole(role) {
    return role === "think" || role === "call" || role === "result"
  }

  // The store is the truth: the streaming tail is a courtesy, and this is what
  // makes the window correct when a turn failed, was interrupted, or wrote more
  // than the stream carried.
  function reloadChat() {
    if (!root.chat) return
    // A chat that does not exist yet has nothing to read: its id arrives with the
    // first message.
    if (root.chat.isNew) return
    // One read at a time: a tick landing while the previous read is still in flight
    // must not queue a second process for the same answer.
    if (threadProc.running) { root.chatRereadPending = true; return }
    root.chatRereadPending = false
    // Stamp the read so its answer can be recognised as belonging to this window.
    root.threadEpoch = root.chatEpoch
    threadProc.command = root.threadCommand()
    threadProc.running = true
  }

  // Take what is in the box and either send it or hold it. Nothing is ever dropped:
  // a chat that is mid-turn, or leased by another surface, queues instead of refusing.
  function sendChat() {
    var text = String(chatInput.text || "")
    if (!root.chat) return
    if (text.trim() === "" && chatAttach.length === 0) return
    // Files ride the turn the way the desktop hands them over: an image goes
    // through --image so the model actually SEES it, anything else becomes an
    // @file: reference the agent inlines. Credential paths are refused by the
    // agent's own deny-list, not by anything here.
    var refs = [], image = ""
    for (var i = 0; i < chatAttach.length; i++) {
      var a = chatAttach[i]
      if (a.image && image === "") image = a.path
      else refs.push("@file:" + (/\s/.test(a.path) ? "`" + a.path + "`" : a.path))
    }
    var body = text
    if (refs.length > 0) body = (body.trim() === "" ? "" : body + "\n") + refs.join(" ")
    if (body.trim() === "") body = "(see the attached image)"
    chatInput.text = ""
    root.clearAttach()
    if (root.chatPending || root.chatHeld !== "") {
      // Deliberately no echo here: the turn has not been handed over, and the poll
      // would wipe it on its next tick. The strip under the box is what says it is
      // waiting, and the echo happens for real when dispatchChat runs.
      chatQueue = chatQueue.concat([{ body: body, image: image }])
      return
    }
    root.dispatchChat(body, image)
  }

  // Hand one message to the agent. Kept apart from sendChat because the queue drains
  // through the same door, and the two must not drift apart.
  function dispatchChat(body, image) {
    // Echo it now: the agent takes a few seconds to even record the turn, and a
    // box that appears to swallow what you typed reads as broken.
    chatTurns = chatTurns.concat([{ role: "user", text: body,
                                    ts: Math.floor(Date.now() / 1000) }])
    chatLive = ""
    chatLiveWork = []
    chatLiveSeen = 0
    chatError = ""
    chatPending = true
    chatSendCount = root.chatRenderedCount
    // A brand-new chat is addressed by NAME: it does not exist yet, so there is no
    // id to resume. Its id arrives on the stream once the first turn creates it.
    var cmd = [root.sender, "--bot", root.chat.bot]
    if (root.chat.isNew) cmd = cmd.concat(["--title", root.chat.title])
    else cmd = cmd.concat(["--session", root.chat.session_id])
    cmd = cmd.concat(["--stream", "--text", body])
    if (image !== "") cmd = cmd.concat(["--image", image])
    sendProc.command = cmd
    sendProc.running = true
    chatFocus.restart()
  }

  // Drain the queue, but only when the chat can actually take a turn.
  function flushQueue() {
    if (chatQueue.length === 0) return
    if (root.chatPending || root.chatHeld !== "" || !root.chat) return
    var head = chatQueue[0]
    chatQueue = chatQueue.slice(1)
    root.dispatchChat(head.body, head.image)
  }

  function dropQueue() { chatQueue = [] }

  // True when the transcript the store just sent is the one already on screen.
  // Assigning a new array rebuilds every turn; the pump reads about once a second, and
  // rebuilding an unchanged transcript is what made the view twitch while you watched it.
  function sameTurns(a) {
    var b = root.chatTurns
    if (!b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++)
      if (a[i].role !== b[i].role || a[i].text !== b[i].text || a[i].ts !== b[i].ts)
        return false
    return true
  }

  // True when this stored turn is the very text the live tail is already showing.
  // While a reply streams, the store can already carry a prefix of it, and drawing both
  // put the answer on screen twice - once with a clock, once without. Clearing the tail
  // to fix that made the words vanish mid-sentence and the view jump, so the stored copy
  // is hidden instead: the live text stays still, and the transcript takes over in one
  // step when the turn ends and the tail is dropped.
  function turnDupesTail(turn, i) {
    var tail = String(root.chatLive)
    if (tail === "" || i !== root.chatTurns.length - 1) return false
    if (String(turn.role) !== "bot") return false
    var stored = String(turn.text || "")
    if (stored === "") return false
    return stored.indexOf(tail) === 0 || tail.indexOf(stored) === 0
  }

  // The old behaviour, kept on its own key: hand the row to Hermes Desktop.
  function openRowInDesktop(index) {
    if (index < 0 || index >= rows.length) return
    var row = rows[index]
    if (row.kind === "bot") root.openBot(row.bot)
    else if (row.kind === "attach" || row.kind === "pinned") root.openSession(row.bot, row.session)
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
    if (row.kind === "bot") {
      // The bot row talks in the bot's own forever-chat, not in whichever visible
      // session happens to be newest. Hermes allows exactly ONE writer per session
      // and the desktop holds a lease on the chat it has open - so a visible
      // session is usually the one that will refuse. The canonical Bot Chat is
      // hidden from the desktop's sidebar, which is what makes it this window's own.
      var own = row.bot.chat || row.bot.attach
      if (own && own.session_id) root.openChat(row.bot, own)
      else root.openBot(row.bot)
    } else if (row.kind === "attach" || row.kind === "pinned") {
      // A session row is the desktop's conversation: it may be open there, and then
      // Hermes will refuse the write. The window says so plainly rather than failing
      // silently.
      root.openChat(row.bot, row.session)
    }
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
    // Open a conversation from outside: `omarchy-shell ozz1ee.hermbot openThread <id>`.
    // Same reason the demo helpers exist - a panel loses focus the moment you type
    // the command in a terminal, so a screenshot run needs a way in that is not a
    // click. It also makes the window reachable from a keybinding later.
    function openThread(sessionId: string): string {
      var sid = String(sessionId || "")
      if (sid === "") return "usage: openThread <session-id>"
      for (var i = 0; i < bots.length; i++) {
        var b = bots[i]
        if (b.chat && String(b.chat.session_id) === sid) {
          root.openChat(b, b.chat)
          return "chat " + sid
        }
        if (b.attach && String(b.attach.session_id) === sid) {
          root.openChat(b, b.attach)
          return "chat " + sid
        }
        var pins = b.pinned || []
        for (var j = 0; j < pins.length; j++) {
          if (String(pins[j].session_id) === sid) {
            root.openChat(b, pins[j])
            return "chat " + sid
          }
        }
      }
      return "no row carries " + sid
    }
    // What the chat window is showing right now. Exists for probes that cannot
    // click or type - a screenshot run, or working out why a key did nothing.
    function chatState(): string { return root.chatStateText() }
    // The same call the `n` key makes, so the key and the function can be told apart.
    function newChat(): string {
      root.startNewChatForCursor()
      return root.chatStateText()
    }
    // Back to the roster without a keystroke, so a probe can reach that state.
    function closeChat(): string {
      root.closeChat()
      return "roster"
    }
    // The file browser and the attachment tray, for a screenshot run: the picker only
    // opens on a click, and a probe has no mouse.
    function picker(dir: string): string {
      if (!root.opened) root.open()
      root.openPicker()
      if (dir) root.browseTo(String(dir))
      return JSON.stringify({ open: root.pickerOpen, dir: root.pickerDir,
                              entries: root.pickerEntries.length })
    }
    function attach(path: string): string {
      if (!root.opened) root.open()
      root.attachFile(String(path))
      return JSON.stringify({ attached: root.chatAttach.length })
    }
    // Put text in the box without a keyboard, and cancel what is queued. A probe has
    // neither, and both states are worth being able to reach from a script.
    function draft(text: string): string {
      if (!root.opened) root.open()
      chatInput.text = String(text)
      return JSON.stringify({ box: Math.round(root.chatBoxHeight),
                              lines: chatInput.lineCount,
                              w: Math.round(chatInput.width),
                              ch: Math.round(chatInput.contentHeight),
                              th: Math.round(chatInput.height) })
    }
    function dropQueued(): string {
      var n = root.chatQueue.length
      root.dropQueue()
      return JSON.stringify({ dropped: n })
    }
    // Drive the resize from outside: a probe has no mouse, and the centring claim
    // ("one edge grows both sides") is only worth anything if it can be measured.
    function resize(w: real, log: real): string {
      if (w > 0) root.chatWidth = root.clampChatWidth(w)
      if (log > 0) root.chatLogBase = root.clampChatLog(log)
      return JSON.stringify({ x: panel.cardOrigin.x, y: panel.cardOrigin.y,
                              w: panel.contentWidth, h: panel.contentHeight,
                              log: Math.round(root.chatLogHeight),
                              wrap: Math.round(turns.width),
                              drag: root.dragWrap })
    }
    // Drive the font scale from outside, and report both the panel's computed sizes and
    // the bar label's - the second must NOT move, or the setting has leaked out of the
    // window into the bar.
    function font(scale: real): string {
      if (scale > 0) root.fontScale = Math.max(root.fontMin, Math.min(root.fontMax, scale))
      return JSON.stringify({ scale: root.fontScale,
                              body: root.fs(Style.font.bodySmall),
                              caption: root.fs(Style.font.caption),
                              bar: Style.font.caption,
                              inputFocus: chatInput.activeFocus,
                              catcherFocus: keyCatcher.activeFocus })
    }
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
    // The chat wants room to read and type in; the roster is a list and stays
    // narrow. Both are clamped to what the screen actually offers.
    contentWidth: panel.fittedContentWidth(root.chat !== null ? root.chatWidth : Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(2), Style.space(930))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the message box holds the keys they are its own: this handler claims
      // j/k/h/l, space, x and Enter, so an unblocked catcher would eat every letter
      // of what you type. This is the upstream panel-editor pattern.
      blocked: root.chat !== null && chatInput.activeFocus

      onMoveRequested: function(dx, dy) {
        if (dx < 0) root.scrub = !root.scrub
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateRow(root.cursor)
      // Esc means "back out of one thing", never "throw everything away". With the
      // browser unfolded it closes the browser and leaves the conversation alone;
      // a second Esc then closes the chat, which is what the footer promises.
      onCloseRequested: if (root.pickerOpen) root.closePicker(); else root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") root.cycleBarMetric()
        else if (t === "g" || t === "G") root.cycleOrdering()
        else if (t === "p" || t === "P") root.togglePinned()
        else if (t === "s" || t === "S") root.cycleSource()
        else if (t === "o" || t === "O") root.openRowInDesktop(root.cursor)
        else if (t === "w" || t === "W") root.toggleWork()
        else if (t === "n" || t === "N") root.startNewChatForCursor()
        // Bare here, not Ctrl-modified: the catcher only gets a key when the composer is
        // NOT holding it, so a lone "+" in this mode has no other meaning to protect.
        else if (t === "+" || t === "=") root.bumpFont(root.fontStep)
        else if (t === "-" || t === "_") root.bumpFont(-root.fontStep)
        else if (t === "0") root.resetFont()
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
        // Exactly the column. The card already carries popupPadding on every side,
        // and slack here stacked on top of it: the gap under the footer came to more
        // than twice the gap above the header, which reads as wasted space.
        contentHeight: column.implicitHeight
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
                font.pixelSize: root.fs(Style.font.caption)
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
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.faint }

          // ---- the chat window ------------------------------------------------
          // Shown instead of the roster when a row opened a conversation. Same
          // fonts, same colours, same spacing as the list, so it reads as this
          // panel rather than a different app.
          Item {
            id: chatView
            width: parent.width
            visible: root.chat !== null
            height: visible ? chatBody.implicitHeight : 0

            Column {
              id: chatBody
              width: parent.width
              spacing: 0

              // ---- who you are talking to, and the way back
              Item {
                width: parent.width
                height: Style.space(30)
                Text {
                  id: backText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "‹ back"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeChat()
                  }
                }
                // The work toggle lives in the header because it changes what the
                // transcript IS, and `w` alone would be undiscoverable.
                Text {
                  id: workText
                  anchors.left: backText.right
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.showWork ? "stream on" : "stream off"
                  color: workToggle.containsMouse ? root.fg : root.faint
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  MouseArea {
                    id: workToggle
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWork()
                  }
                }
                // A fresh conversation, started here rather than in the desktop.
                Text {
                  id: newText
                  anchors.left: workText.right
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "+ new"
                  color: newArea.containsMouse ? root.fg : root.accent
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  MouseArea {
                    id: newArea
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startNewChat(root.botByName(root.chat ? root.chat.bot : ""))
                  }
                }
                // A chat that does not exist yet says so AND says who it is with: `n`
                // acts on the row under the cursor, and a conversation with an
                // unnamed bot is not something to type into.
                Text {
                  id: newNoteText
                  anchors.left: newText.right
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  visible: root.chat !== null && root.chat.isNew === true
                  text: "new chat with @" + (root.chat ? root.chat.bot : "")
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
                // A held chat is not a detail: it means nothing you type can be
                // written, so it is said in the header rather than discovered by a
                // send that goes nowhere. It sits in the LEFT chain with the other
                // state markers - right-aligned it landed on top of the title.
                Text {
                  anchors.left: newNoteText.visible ? newNoteText.right : newText.right
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  visible: root.chatHeld !== ""
                  text: "held by " + root.chatHeld
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(300)
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideLeft
                  textFormat: Text.PlainText
                  text: root.chat ? (root.chat.title + "  @" + root.chat.bot) : ""
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }

              Rectangle { width: parent.width; height: 1; color: root.faint }

              // ---- the transcript, always parked on the newest turn
              Flickable {
                id: transcript
                width: parent.width
                // The log yields exactly what the composer takes, so the window keeps
                // its size while the box grows into the room.
                height: root.chatLogHeight
                contentWidth: width
                contentHeight: turns.implicitHeight + Style.space(8)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                Column {
                  id: turns
                  x: Style.space(4)
                  width: root.dragWrap > 0 ? root.dragWrap : parent.width - Style.space(8)
                  topPadding: Style.space(4)
                  spacing: Style.space(6)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: root.chatLoading && root.chatTurns.length === 0
                    text: "reading the conversation…"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: !root.chatLoading && root.chatTurns.length === 0 && root.chatLive === ""
                    text: "nothing said here yet."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }

                  Repeater {
                    model: root.chatTurns

                    Column {
                      id: turnBlock
                      required property var modelData
                      width: turns.width
                      spacing: Style.space(1)
                      // The live tail below is already showing this same reply. Drawing
                      // the stored copy as well is what printed the answer twice; hiding
                      // it here - instead of clearing the tail - keeps the words still
                      // while they arrive. When the turn ends the tail goes and this
                      // takes over in one step.
                      visible: !root.turnDupesTail(turnBlock.modelData, turnBlock.index)
                      height: visible ? implicitHeight : 0

                      Row {
                        spacing: Style.space(6)
                        Text {
                          textFormat: Text.PlainText
                          text: root.isWorkRole(turnBlock.modelData.role)
                                ? root.workLabel(turnBlock.modelData.role,
                                                 turnBlock.modelData.text)
                                : root.roleLabel(turnBlock.modelData.role,
                                                 root.chat ? root.chat.bot : "")
                          color: root.roleColor(turnBlock.modelData.role)
                          font.family: root.fontFamily
                          font.pixelSize: root.fs(Style.font.caption)
                        }
                        Text {
                          textFormat: Text.PlainText
                          visible: !root.isWorkRole(turnBlock.modelData.role)
                                   && root.clockOf(turnBlock.modelData.ts) !== ""
                          text: root.clockOf(turnBlock.modelData.ts)
                          color: root.faint
                          font.family: root.fontFamily
                          font.pixelSize: root.fs(Style.font.caption)
                        }
                        Text {
                          textFormat: Text.PlainText
                          visible: root.isWorkRole(turnBlock.modelData.role)
                          text: root.workExpanded[turnBlock.index] ? "less" : "more"
                          color: root.faint
                          font.family: root.fontFamily
                          font.pixelSize: root.fs(Style.font.caption)
                          MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleWorkRow(turnBlock.index)
                          }
                        }
                      }
                      // Anything the turn carried as an image, drawn as itself.
                      Repeater {
                        model: root.imagePathsIn(turnBlock.modelData.text,
                                                 turnBlock.modelData.role)

                        Rectangle {
                          id: shot
                          required property string modelData
                          width: Math.min(Style.space(380), turns.width)
                          height: Style.space(210)
                          color: "transparent"
                          border.color: root.faint
                          border.width: 1
                          // A path that only looks like an image - prose in a message that
                          // happens to end in .png - cannot be drawn. Left alone, the
                          // failed load retries forever and the shell sits at 90% CPU.
                          visible: shotImg.status !== Image.Error

                          Image {
                            id: shotImg
                            anchors.fill: parent
                            anchors.margins: 1
                            source: "file://" + shot.modelData
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 760
                            sourceSize.height: 420
                            onStatusChanged: if (status === Image.Error) source = ""
                          }
                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["xdg-open", shot.modelData])
                          }
                        }
                      }
                      Text {
                        width: parent.width
                        visible: text !== ""
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        // The work can run long, and it is context rather than the
                        // conversation: a few lines until you ask for the rest.
                        maximumLineCount: root.isWorkRole(turnBlock.modelData.role)
                                          && !root.workExpanded[turnBlock.index] ? 4 : 100000
                        elide: root.isWorkRole(turnBlock.modelData.role)
                               && !root.workExpanded[turnBlock.index] ? Text.ElideRight
                                                                      : Text.ElideNone
                        text: root.richText(root.isWorkRole(turnBlock.modelData.role)
                              ? root.workBody(turnBlock.modelData.role,
                                              root.workShown(turnBlock.modelData.text,
                                                             turnBlock.index))
                              : root.textWithoutImages(turnBlock.modelData.text,
                                                       turnBlock.modelData.role))
                        color: root.isWorkRole(turnBlock.modelData.role)
                               ? (turnBlock.modelData.role === "result" ? root.dim : root.faint)
                               : root.fg
                        linkColor: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.bodySmall)
                        onLinkActivated: function(link) { root.openLink(link) }
                      }
                    }
                  }

                  // What the bot is doing right now, straight off the stream: the
                  // desktop's "it is working" made visible while it works.
                  Repeater {
                    model: root.chatLiveWork

                    Column {
                      id: liveWork
                      required property var modelData
                      width: turns.width
                      spacing: Style.space(1)
                      // The live tail obeys the same switch as the history. Leaving it
                      // unconditional made `stream off` mean "shown while it runs, then
                      // gone" - which reads as a glitch, not a setting.
                      visible: root.showWork
                      height: visible ? implicitHeight : 0

                      Text {
                        textFormat: Text.PlainText
                        text: root.workLabel(liveWork.modelData.role, liveWork.modelData.text)
                        color: root.roleColor(liveWork.modelData.role)
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                      }
                      Text {
                        width: parent.width
                        visible: text !== ""
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        text: root.richText(root.workBody(liveWork.modelData.role,
                                                          liveWork.modelData.text))
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.bodySmall)
                      }
                    }
                  }

                  // The reply as it is written, before the store has it.
                  Column {
                    width: turns.width
                    spacing: Style.space(1)
                    visible: root.chatLive !== ""
                    Text {
                      textFormat: Text.PlainText
                      text: "@" + (root.chat ? root.chat.bot : "")
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: root.fs(Style.font.caption)
                    }
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      text: root.chatLive
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: root.fs(Style.font.bodySmall)
                    }
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: root.chatPending && root.chatLive === ""
                    text: "thinking…"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }
                }
              }

              Rectangle { width: parent.width; height: 1; color: root.faint }

              // ---- files queued for the next turn
              Flow {
                width: parent.width
                spacing: Style.space(4)
                topPadding: Style.space(4)
                visible: root.chatAttach.length > 0

                Repeater {
                  model: root.chatAttach

                  Rectangle {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property bool isImage: !!modelData.image
                    width: Math.min(chipRow.implicitWidth + Style.space(14), turns.width)
                    height: isImage ? Style.space(40) : Style.space(18)
                    color: "transparent"
                    border.color: root.faint
                    border.width: 1
                    radius: 2

                    Row {
                      id: chipRow
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      // An image you are about to send, shown as itself. Without it
                      // the only clue is a filename, which is not what you check.
                      Image {
                        visible: chip.isImage
                        source: chip.isImage ? "file://" + chip.modelData.path : ""
                        width: Style.space(32)
                        height: Style.space(32)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 128
                        sourceSize.height: 128
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: (chip.isImage ? "" : "▤ ") + chip.modelData.name
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                        elide: Text.ElideMiddle
                        height: chip.height
                        verticalAlignment: Text.AlignVCenter
                        width: Math.min(implicitWidth, Style.space(150))
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: "×"
                        color: chipDrop.containsMouse ? root.urgent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                        height: chip.height
                        verticalAlignment: Text.AlignVCenter
                        MouseArea {
                          id: chipDrop
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.detachFile(chip.index)
                        }
                      }
                    }
                  }
                }
              }

              // ---- the box
              Item {
                width: parent.width
                height: root.chatBoxHeight

                // Attach: folds the browser open, and folds it back. It has to be a
                // toggle - the browser sits over the conversation, so the same click
                // that summoned it is the one that has to take it away when you
                // change your mind. A one-way button here strands you in the listing.
                Text {
                  id: attachButton
                  anchors.left: parent.left
                  // Pinned to the first line rather than centred: the box grows
                  // downward, and a centred button would drift into the middle of a
                  // paragraph the moment you paste one.
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(15)
                  textFormat: Text.PlainText
                  text: "＋"
                  color: root.pickerOpen ? root.fg
                                         : (attachArea.containsMouse ? root.fg : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.bodySmall)
                  MouseArea {
                    id: attachArea
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickerOpen ? root.closePicker() : root.openPicker()
                  }
                }

                // A TextArea, not a TextField: this one wraps, and it reports the height
                // its text actually needs - which is what lets the box grow with a
                // dictation or a paste instead of scrolling it sideways along one
                // endless line you cannot read.
                TextArea {
                  id: chatInput
                  anchors.left: attachButton.right
                  anchors.leftMargin: Style.space(14)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(14)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(13)
                  height: root.chatInputHeight
                  // Always writable. A chat mid-turn, or a lease held by another
                  // surface, no longer stops you composing: the message queues and
                  // leaves on its own. Locking the box meant waiting for someone else's
                  // turn to end before you could even write the sentence.
                  enabled: true
                  wrapMode: TextArea.Wrap
                  textFormat: TextEdit.PlainText
                  placeholderText: root.chatHeld !== ""
                                   ? "held by " + root.chatHeld + " - your message will queue"
                                   : (root.chatPending
                                      ? "the bot is thinking - type on, it will queue"
                                      : "message @" + (root.chat ? root.chat.bot : ""))
                  color: root.fg
                  placeholderTextColor: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.bodySmall)
                  selectByMouse: true
                  background: Rectangle {
                    color: "transparent"
                    border.color: chatInput.activeFocus ? root.divider : root.faint
                    border.width: 1
                    radius: 2
                  }
                  // Enter sends, Shift+Enter is a line break - the convention the
                  // desktop uses, and the only way to write a paragraph in a box that
                  // grows.
                  Keys.onReturnPressed: function(event) {
                    if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                    root.sendChat()
                    event.accepted = true
                  }
                  Keys.onEnterPressed: function(event) {
                    if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                    root.sendChat()
                    event.accepted = true
                  }
                  Keys.onEscapePressed: root.pickerOpen ? root.closePicker() : root.closeChat()
                  // The catcher is blocked while this field holds the keys, so Ctrl+= and
                  // Ctrl+- would otherwise only work while reading, never while typing -
                  // which is exactly when you notice the text is too small.
                  Keys.onPressed: function(event) {
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                      root.bumpFont(root.fontStep); event.accepted = true
                    } else if (event.key === Qt.Key_Minus) {
                      root.bumpFont(-root.fontStep); event.accepted = true
                    } else if (event.key === Qt.Key_0) {
                      root.resetFont(); event.accepted = true
                    }
                  }
                  onVisibleChanged: if (visible) chatFocus.restart()
                }

                // Deliberately no send button. Enter sends and Shift+Enter breaks the
                // line, so the button only ever duplicated the key your hand was
                // already on - and it cost the field a strip of width for it.
              }

              // What is waiting for the chat to free up. Without this the queue would be
              // invisible, and a message you typed would look lost - which is the exact
              // fear the old lock was built on.
              Item {
                width: parent.width
                height: visible ? Style.space(24) : 0
                visible: root.chatQueue.length > 0
                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(70)
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.chatQueue.length > 0
                        ? "⏳ waiting to send: "
                          + String(root.chatQueue[0].body || "").split("\n")[0]
                        : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.chatQueue.length > 1
                        ? "✕ drop all " + root.chatQueue.length : "✕ drop"
                  color: dropArea.containsMouse ? root.urgent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  MouseArea {
                    id: dropArea
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dropQueue()
                  }
                }
              }

              // The way out of a held chat, in one click: the bot's own Bot Chat is
              // the one conversation nothing else holds.
              Text {
                width: parent.width
                visible: root.chatHeld !== "" && root.canSwitchToBotChat()
                textFormat: Text.PlainText
                topPadding: Style.space(3)
                text: "→ talk in @" + (root.chat ? root.chat.bot : "")
                      + "'s own Bot Chat instead"
                color: switchArea.containsMouse ? root.fg : root.accent
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
                MouseArea {
                  id: switchArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchToBotChat()
                }
              }

              // ---- whatever went wrong, in the agent's own words
              Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                visible: root.chatError !== ""
                topPadding: Style.space(2)
                text: root.chatError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }

              // ---- the file browser, unfolding downward under the box
              Item {
                id: browserView
                width: parent.width
                visible: root.pickerOpen
                height: visible ? browserBody.implicitHeight : 0

                Column {
                  id: browserBody
                  width: parent.width
                  spacing: 0

                  Rectangle { width: parent.width; height: 1; color: root.faint }

                  // where we are, the way up, and the way out
                  Item {
                    width: parent.width
                    height: Style.space(28)
                    Text {
                      id: upLabel
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "‹ up"
                      color: root.pickerParent !== "" ? root.dim : root.faint
                      font.family: root.fontFamily
                      font.pixelSize: root.fs(Style.font.caption)
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(5)
                        enabled: root.pickerParent !== ""
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.browseTo(root.pickerParent)
                      }
                    }
                    // A way out the mouse can reach. Esc does the same thing, but the
                    // browser is summoned by a click, so it has to be dismissable by
                    // one too - otherwise a hand that never leaves the mouse is stuck
                    // staring at a directory listing it cannot put away.
                    Text {
                      id: closeLabel
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "✕ close"
                      color: closeArea.containsMouse ? root.fg : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fs(Style.font.caption)
                      MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -Style.space(5)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closePicker()
                      }
                    }
                    Text {
                      anchors.left: upLabel.right
                      anchors.right: closeLabel.left
                      anchors.leftMargin: Style.space(12)
                      anchors.rightMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      horizontalAlignment: Text.AlignRight
                      elide: Text.ElideLeft
                      textFormat: Text.PlainText
                      text: root.pickerDir
                      color: root.faint
                      font.family: root.fontFamily
                      font.pixelSize: root.fs(Style.font.caption)
                    }
                  }

                  Rectangle { width: parent.width; height: 1; color: root.faint }

                  Flickable {
                    id: listing
                    width: parent.width
                    height: Style.space(280)
                    contentWidth: width
                    contentHeight: files.implicitHeight + Style.space(8)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    interactive: contentHeight > height
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                      id: files
                      x: Style.space(4)
                      width: parent.width - Style.space(8)
                      topPadding: Style.space(4)
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        visible: root.pickerEntries.length === 0 && root.pickerError === ""
                        text: "nothing here"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        visible: root.pickerError !== ""
                        text: root.pickerError
                        color: root.urgent
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                      }

                      Repeater {
                        model: root.pickerEntries

                        Item {
                          id: entryRow
                          required property var modelData
                          required property int index
                          width: files.width
                          height: Style.space(20)

                          Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -Style.space(4)
                            anchors.rightMargin: -Style.space(4)
                            color: entryArea.containsMouse ? root.hilite : "transparent"
                          }
                          Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(6)
                            Text {
                              textFormat: Text.PlainText
                              text: entryRow.modelData.dir ? "▸" : " "
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: root.fs(Style.font.caption)
                            }
                            Text {
                              textFormat: Text.PlainText
                              text: entryRow.modelData.name + (entryRow.modelData.dir ? "/" : "")
                              color: entryRow.modelData.dir ? root.fg : root.dim
                              font.family: root.fontFamily
                              font.pixelSize: root.fs(Style.font.bodySmall)
                              elide: Text.ElideMiddle
                              width: Math.min(implicitWidth, files.width - Style.space(96))
                            }
                            Text {
                              textFormat: Text.PlainText
                              visible: !entryRow.modelData.dir
                              text: root.humanSize(entryRow.modelData.size)
                              color: root.faint
                              font.family: root.fontFamily
                              font.pixelSize: root.fs(Style.font.caption)
                            }
                          }
                          MouseArea {
                            id: entryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickEntry(entryRow.modelData)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- rows
          Repeater {
            id: repeater
            model: root.rows

            Item {
              id: rowItem
              required property var modelData
              required property int index
              width: column.width
              // The roster stands down while a conversation is open. A Repeater
              // parents its delegates to its PARENT, not to itself, so hiding the
              // Repeater would not have hidden these.
              visible: root.chat === null
              height: !visible ? 0
                    : modelData.kind === "section" || modelData.kind === "pinnedHeader" ? Style.space(26)
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

              // Bots with news get greeted when the panel opens - Rakabot's own
              // line, `unread > 0`. Nothing else waves: the news is what the wave
              // is about, and this is now driven by real unread state.
              readonly property bool wantsGreeting: modelData.kind === "bot"
                && !!modelData.bot.waiting

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
                font.pixelSize: root.fs(Style.font.caption)
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
                font.pixelSize: root.fs(Style.font.caption)
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
                font.pixelSize: root.fs(Style.font.caption)
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
                font.pixelSize: root.fs(Style.font.caption)
              }
              Text {
                textFormat: Text.PlainText
                visible: modelData.kind === "pinnedAgent"
                anchors.left: parent.left
                anchors.leftMargin: Style.space(9)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)
                // Only a pinnedAgent row owns a `bot`. This binding runs for every
                // row regardless of `visible`, so a section, rule or pinnedHeader
                // row would otherwise read `.title` off undefined - the same hole
                // the session line above had.
                text: root.label(String((modelData.bot || {}).title || (modelData.bot || {}).name || "")).toUpperCase()
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
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
                        // Rakabot's own line is `focused ? accent : fg`, and its
                        // `focused` is a dead field - both writers set it to False
                        // and nothing ever raises it - so its names are always the
                        // foreground. Mirroring the expression means mirroring that
                        // outcome; tinting a waiting bot here (it used to take
                        // `urgent`) is what made this roster's names red where the
                        // sibling's are cream. Weight and the badge already carry
                        // "this one wants you".
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.bodySmall)
                        font.bold: modelData.kind === "bot"
                          && (modelData.bot.waiting || (modelData.bot.chat && modelData.bot.chat.unread))
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.kind === "bot" ? root.label(modelData.bot.handle || "") : ""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
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
                      font.pixelSize: root.fs(Style.font.caption)
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
                      font.pixelSize: root.fs(Style.font.caption)
                    }
                    Rectangle {
                      anchors.right: parent.right
                      // A count on the bot that is waiting on you - Rakabot's own
                      // badge - and a dot on the session rows the desktop paints
                      // green. `chat.unread` alone is never true here: it is the
                      // backend watermark, which nothing stamps.
                      visible: modelData.kind === "bot" ? !!modelData.bot.waiting
                             : (modelData.kind === "attach" || modelData.kind === "pinned")
                               ? !!(modelData.session || {}).unread : false
                      width: Math.max(Style.space(14), unreadText.implicitWidth + Style.space(6))
                      height: Style.space(14)
                      radius: height / 2
                      color: root.accent
                      Text {
                        textFormat: Text.PlainText
                        id: unreadText
                        anchors.centerIn: parent
                        // The watcher's count of messages since the app last had
                        // this chat read, so a wide number widens the pill.
                        text: modelData.kind === "bot"
                          ? String(modelData.bot.unread_count || 1) : "\u2022"
                        color: Color.background
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
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
            visible: root.snap && root.bots.length === 0 && root.chat === null
            width: parent.width
            topPadding: Style.space(10)
            text: "no bots in this Hermes install yet"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Rectangle { width: parent.width; height: 1; color: root.faint; visible: root.bots.length > 0 && root.chat === null }


          // ---- footer
          // Two lines, not one. The list of keys is longer than the card is wide, and
          // a single line could only ever be elided. The split is by ROLE: what you
          // press to act, and what the panel is currently set to - so the second line
          // doubles as a readout. The keys are bolded so the eye finds them, and `h`
          // is gone: it was advertised here and had no handler anywhere.
          Item {
            id: footer
            width: parent.width
            visible: root.chat === null
            height: visible ? Style.space(30) : 0

            // Values here are our own enum settings, never user content, so this line
            // may carry markup. The transcript never does.
            readonly property string actLine: "<b>j/k</b> move · <b>⏎</b> open · <b>o</b> desktop · <b>n</b> new "
                                              + (root.newBot !== "" ? root.newBot : "chat")
            readonly property string showLine: "<b>g</b> " + root.ordering + " · <b>p</b> pinned · <b>s</b> "
                                               + root.source + " · <b>r</b> " + root.barMetric
                                               + " · <b>+/-</b> text " + Math.round(root.fontScale * 100) + "%"

            // The two lines are centred as a block and within themselves, so the
            // footer reads as a caption under the card rather than a column of
            // left-hugging text. The width follows the longer line, clamped to the
            // card, so a narrow theme still elides instead of overflowing.
            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(Math.max(actText.implicitWidth, showText.implicitWidth),
                              parent.width)
              spacing: Style.space(1)

              Text {
                id: actText
                textFormat: Text.RichText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: footer.actLine
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Text {
                id: showText
                textFormat: Text.RichText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: footer.showLine
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
            }
          }
        }
      }

      // ---- resizing the window -----------------------------------------------
      // Three grips, and they live INSIDE the card: the layer-shell surface's input
      // mask is the card rect, so a grip hanging outside it would never see the mouse.
      // They are the last children here, so they sit on top of the content.
      //
      // Horizontal drags are doubled on purpose. The panel keeps itself centred
      // (x = screenW/2 - contentWidth/2), so pushing the right edge out by dx also
      // pushes the left edge out by dx: the window grows by 2*dx, around its own
      // centre. That is what makes one edge read as "bigger" instead of "shifted
      // sideways". Vertically the card is pinned under the bar and can only grow
      // downward, so that drag is 1:1 - the bottom edge follows the pointer.
      MouseArea {
        id: gripRight
        visible: root.chat !== null
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: parent.height - Style.space(80)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeHorCursor
        property real startW: 0
        property real startGX: 0
        onPressed: function(mouse) {
          startW = root.chatWidth
          startGX = gripRight.mapToGlobal(mouse.x, mouse.y).x
          root.beginDrag()
        }
        onReleased: root.endDrag()
        onCanceled: root.endDrag()
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var dx = gripRight.mapToGlobal(mouse.x, mouse.y).x - startGX
          root.chatWidth = root.clampChatWidth(startW + dx * 2)
        }
        // A short mark at the middle of the edge, not a line down all of it: enough to
        // say "you can grab here", quiet enough to forget once you know.
        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 2
          height: Style.space(26)
          radius: 1
          color: gripRight.containsMouse ? root.accent : root.faint
        }
      }

      MouseArea {
        id: gripBottom
        visible: root.chat !== null
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(7)
        width: parent.width - Style.space(80)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeVerCursor
        property real startL: 0
        property real startGY: 0
        onPressed: function(mouse) {
          startL = root.chatLogBase
          startGY = gripBottom.mapToGlobal(mouse.x, mouse.y).y
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var dy = gripBottom.mapToGlobal(mouse.x, mouse.y).y - startGY
          root.chatLogBase = root.clampChatLog(startL + dy)
        }
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          height: 2
          width: Style.space(26)
          radius: 1
          color: gripBottom.containsMouse ? root.accent : root.faint
        }
      }

      // The corner does both at once, so the whole window can be scaled in one gesture.
      MouseArea {
        id: gripCorner
        visible: root.chat !== null
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(16)
        height: Style.space(16)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeFDiagCursor
        property real startW: 0
        property real startL: 0
        property real startGX: 0
        property real startGY: 0
        onPressed: function(mouse) {
          startW = root.chatWidth
          startL = root.chatLogBase
          var p = gripCorner.mapToGlobal(mouse.x, mouse.y)
          startGX = p.x
          startGY = p.y
          root.beginDrag()
        }
        onReleased: root.endDrag()
        onCanceled: root.endDrag()
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var p = gripCorner.mapToGlobal(mouse.x, mouse.y)
          root.chatWidth = root.clampChatWidth(startW + (p.x - startGX) * 2)
          root.chatLogBase = root.clampChatLog(startL + (p.y - startGY))
        }
        // A mark, so the grip can be found without hunting for the cursor change.
        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(2)
          anchors.bottomMargin: Style.space(1)
          textFormat: Text.PlainText
          text: "◢"
          color: gripCorner.containsMouse ? root.accent : root.faint
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.caption)
        }
      }
    }
  }
}

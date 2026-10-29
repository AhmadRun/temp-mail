import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TempMail.js" as TM
import "components"

// Disposable email in the bar: a 10/30-minute address from mail.tm, a
// countdown, an inbox popup and a plain-text message view. All network
// calls (and the account token) live in bin/temp-mail.
Panel {
  id: root
  moduleName: "io.github.ahmadrun.temp-mail"
  ipcTarget: "io.github.ahmadrun.temp-mail"

  // nf-md-email_outline
  readonly property string mailGlyph: "󰇮"

  // ---- Settings (shell.json via the plugin settings form)
  readonly property int defaultDuration: String(setting("defaultDuration", "10")) === "30" ? 30 : 10
  readonly property int extendMinutes: Math.max(1, Math.min(30, Number(setting("extendMinutes", 10)) || 10))
  readonly property int pollSeconds: Math.max(3, Math.min(60, Number(setting("pollSeconds", 5)) || 5))
  readonly property bool notifyNewMail: setting("notifyNewMail", true) !== false
  readonly property bool iconOnly: setting("iconOnly", false) === true

  // ---- Address state (~/.local/state/omarchy/settings/temp-mail.json)
  property string address: ""
  property real expiresAt: 0   // unix seconds
  readonly property bool hasAddress: address !== ""
  property date now: new Date()
  readonly property real msLeft: hasAddress ? expiresAt * 1000 - now.getTime() : 0
  property int chosenMinutes: defaultDuration

  // ---- Inbox
  property var messages: []
  property var knownIds: ({})
  property bool inboxLoaded: false
  property string errorText: ""
  property int selectedIndex: 0
  readonly property int unreadCount: {
    var n = 0
    for (var i = 0; i < messages.length; i++) if (!messages[i].seen) n++
    return n
  }

  // ---- Message view
  property var current: null       // parsed `temp-mail read` result
  property bool loadingMessage: false
  readonly property var currentCodes: current ? TM.findCodes(current.subject, current.text, current.verifications) : []

  property bool warned: false
  property bool expiring: false

  readonly property string barText: {
    if (!hasAddress || iconOnly || (bar && bar.vertical)) return unreadCount > 0 && !(bar && bar.vertical) ? mailGlyph + " " + unreadCount : mailGlyph
    return mailGlyph + (unreadCount > 0 ? " " + unreadCount + " ·" : "") + " " + TM.formatCountdown(msLeft)
  }

  function resolvePath(relative) {
    var url = String(Qt.resolvedUrl(relative))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  function notify(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "-a", "Temp Mail", "-u", urgency || "normal", title, body])
  }

  // The payload goes to wl-copy on stdin, never argv: process arguments are
  // world-readable through /proc/<pid>/cmdline and the text can be a
  // verification code.
  function copy(text, label) {
    if (!text) return
    var proc = clipboardProcess.createObject(root, { payload: String(text) })
    proc.running = true
    notify("Copied " + (label || "to clipboard"), "", "low")
  }

  function openUrl(url) {
    Util.execArgv(["omarchy-launch-browser", url])
  }

  // ---- Helper queue: one bin/temp-mail call at a time

  property var queue: []
  function run(args, kind) {
    queue.push({ args: args, kind: kind })
    flush()
  }
  function flush() {
    if (helper.running || queue.length === 0) return
    var job = queue.shift()
    helper.kind = job.kind
    helper.command = ["bash", resolvePath("bin/temp-mail")].concat(job.args)
    helper.running = true
  }

  function createAddress(minutes) {
    current = null
    messages = []
    knownIds = {}
    inboxLoaded = false
    warned = false
    run(["new", String(minutes || chosenMinutes)], "new")
  }
  function extend() { if (hasAddress) { warned = false; run(["extend", String(extendMinutes)], "extend") } }
  function removeAddress() {
    current = null
    messages = []
    knownIds = {}
    run(["delete"], "delete")
  }
  function refresh() { if (hasAddress && !helper.running && queue.length === 0) run(["messages"], "messages") }
  function openMessage(m) {
    if (!m) return
    loadingMessage = true
    current = { id: m.id, from: m.from, fromName: m.fromName, subject: m.subject, createdAt: m.createdAt,
                text: m.intro, verifications: [], hasHtml: false, attachments: [] }
    run(["read", m.id], "read")
  }
  function deleteMessage(id) {
    if (!id) return
    var next = []
    for (var i = 0; i < messages.length; i++) if (messages[i].id !== id) next.push(messages[i])
    messages = next
    selectedIndex = Math.min(selectedIndex, Math.max(0, next.length - 1))
    current = null
    run(["delete-message", id], "ignore")
  }

  function handleResult(kind, out) {
    var data = TM.parseJson(out, null)
    if (data && data.error) {
      errorText = data.error
      if (kind === "read") loadingMessage = false
      return
    }
    errorText = ""
    if (kind === "new" && data) {
      address = data.address || ""
      expiresAt = Number(data.expiresAt) || 0
      if (address) copy(address, "new address")
      refresh()
    } else if (kind === "extend" && data) {
      expiresAt = Number(data.expiresAt) || expiresAt
    } else if (kind === "delete") {
      address = ""
      expiresAt = 0
    } else if (kind === "messages" && Array.isArray(data)) {
      var fresh = []
      var ids = {}
      for (var i = 0; i < data.length; i++) {
        ids[data[i].id] = true
        if (inboxLoaded && !knownIds[data[i].id]) fresh.push(data[i])
      }
      knownIds = ids
      messages = data
      if (notifyNewMail && fresh.length > 0) {
        // Sender only: notify-send arguments are world-readable, and
        // subjects often carry verification codes.
        notify(fresh.length === 1 ? "New email" : fresh.length + " new emails",
          "from " + TM.senderLabel(fresh[0].fromName, fresh[0].from), "normal")
      }
      inboxLoaded = true
    } else if (kind === "read" && data && current && data.id === current.id) {
      current = data
      loadingMessage = false
      for (var j = 0; j < messages.length; j++) {
        if (messages[j].id === data.id && !messages[j].seen) {
          var copyList = messages.slice()
          copyList[j] = Object.assign({}, messages[j], { seen: true })
          messages = copyList
        }
      }
    }
  }

  function checkExpiry() {
    if (!hasAddress || expiring) return
    if (msLeft <= 0) {
      expiring = true
      notify("Temp address expired", address + " was deleted", "normal")
      removeAddress()
    } else if (msLeft <= 60000 && !warned) {
      warned = true
      notify("Temp address: 1 minute left", "Open Temp Mail and press + to extend", "normal")
    }
  }

  // ---- Panel lifecycle

  function close() {
    current = null
    controller.hide()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: stateFile.reload()

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/temp-mail.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var data = TM.parseJson(text(), {})
      var addr = data.address || ""
      if (addr !== root.address) {
        root.messages = []
        root.knownIds = {}
        root.inboxLoaded = false
        root.current = null
      }
      root.address = addr
      root.expiresAt = Number(data.expiresAt) || 0
      root.expiring = false
      root.now = new Date()
      root.checkExpiry()
      root.refresh()
    }
    onLoadFailed: {
      root.address = ""
      root.expiresAt = 0
      root.expiring = false
    }
  }

  Process {
    id: helper
    property string kind: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleResult(helper.kind, String(text || ""))
    }
    onExited: root.flush()
  }

  // One short-lived wl-copy per copy(): stdin closes after the write, which
  // a Process cannot reopen, so each copy gets a fresh instance.
  Component {
    id: clipboardProcess
    Process {
      property string payload: ""
      command: ["wl-copy"]
      stdinEnabled: true
      onStarted: {
        write(payload)
        stdinEnabled = false
      }
      onExited: destroy()
    }
  }

  // Extra controls for keybinds:
  //   omarchy-shell io.github.ahmadrun.temp-mail.mail create 10
  IpcHandler {
    target: "io.github.ahmadrun.temp-mail.mail"

    function create(minutes: int): void { root.createAddress(minutes === 30 ? 30 : 10) }
    function copy(): void { root.copy(root.address, "address") }
    function extend(): void { root.extend() }
    function remove(): void { root.removeAddress() }
  }

  Timer {
    interval: 1000
    running: root.hasAddress
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.now = new Date()
      root.checkExpiry()
    }
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: root.hasAddress
    repeat: true
    onTriggered: root.refresh()
  }

  // ---- Bar pill

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.unreadCount > 0
    activeColor: Color.accent
    horizontalMargin: 8.75
    fixedWidth: root.bar && root.bar.vertical ? Style.bar.statusSlot : -1
    tooltipText: root.hasAddress
      ? root.address + " · " + TM.formatCountdown(root.msLeft) + " left"
      : "Temp Mail: click to create a throwaway address"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.hasAddress ? root.copy(root.address, "address") : root.createAddress()
      else root.toggle()
    }
  }

  // ---- Popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property string fontName: root.bar ? root.bar.fontFamily : Style.font.family

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.current ? root.current = null : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.current) {
          bodyFlick.contentY = Math.max(0, Math.min(bodyFlick.contentHeight - bodyFlick.height, bodyFlick.contentY + dy * Style.space(40)))
        } else if (root.messages.length > 0) {
          root.selectedIndex = Math.max(0, Math.min(root.messages.length - 1, root.selectedIndex + dy))
        }
      }
      onActivateRequested: if (!root.current) root.openMessage(root.messages[root.selectedIndex])
      onReturnRequested: if (!root.current) root.openMessage(root.messages[root.selectedIndex])
      onDeleteRequested: root.deleteMessage(root.current ? root.current.id : (root.messages[root.selectedIndex] || {}).id)
      onTextKey: function(t) {
        if (t === "c") root.copy(root.address, "address")
        else if (t === "n") root.createAddress()
        else if (t === "r") root.refresh()
        else if (t === "+") root.extend()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---- Hero: address + countdown
        PanelHero {
          width: parent.width
          foreground: panel.fg
          fontFamily: panel.fontName
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.mailGlyph
              color: root.unreadCount > 0 ? Color.accent : panel.fg
              font.family: panel.fontName
              font.pixelSize: Style.font.display
            }
          }
          title: root.hasAddress ? root.address : (helper.running ? "Creating address…" : "No address yet")
          meta: root.hasAddress
            ? "expires in " + TM.formatCountdown(root.msLeft)
            : "A throwaway inbox for sign-ups"
          detail: root.errorText !== "" ? "⚠ " + root.errorText : ""
        }

        // ---- Address actions
        Row {
          visible: root.hasAddress
          spacing: Style.spacing.md

          Button {
            text: "Copy"
            iconText: "󰆏"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.copy(root.address, "address")
          }
          Button {
            text: "+" + root.extendMinutes + " min"
            iconText: "󰔛"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.extend()
          }
          Button {
            text: "New"
            iconText: "󰑐"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.createAddress()
          }
          Button {
            text: "Delete"
            iconText: "󰆴"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.removeAddress()
          }
        }

        // ---- Lifetime picker + create
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: !root.hasAddress || !root.current

          PanelSectionHeader {
            text: root.hasAddress ? "NEXT ADDRESS LIFETIME" : "LIFETIME"
            foreground: panel.fg
            fontFamily: panel.fontName
          }

          ButtonGroup {
            options: [
              { value: 10, label: "10 min" },
              { value: 30, label: "30 min" }
            ]
            value: root.chosenMinutes
            foreground: panel.fg
            fontFamily: panel.fontName
            focusable: false
            onChanged: function(value) { root.chosenMinutes = Number(value) }
          }

          Button {
            visible: !root.hasAddress
            text: "Create address"
            iconText: "󰇮"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.createAddress()
          }
        }

        PanelSeparator { foreground: panel.fg; visible: root.hasAddress }

        // ---- Inbox view
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.hasAddress && !root.current

          Item {
            width: parent.width
            implicitHeight: refreshButton.implicitHeight

            PanelSectionHeader {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "INBOX · " + root.messages.length + (root.unreadCount > 0 ? " · " + root.unreadCount + " NEW" : "")
              foreground: panel.fg
              fontFamily: panel.fontName
            }
            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Check now (r)"
              foreground: panel.fg
              fontFamily: panel.fontName
              onClicked: root.refresh()
            }
          }

          Text {
            visible: root.messages.length === 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.inboxLoaded
              ? "Waiting for mail… checks every " + root.pollSeconds + " s"
              : "Loading inbox…"
            color: Qt.darker(panel.fg, 1.5)
            font.family: panel.fontName
            font.pixelSize: Style.font.body
          }

          Flickable {
            visible: root.messages.length > 0
            width: parent.width
            height: Math.min(listColumn.implicitHeight, Style.space(44) * 6 + Style.space(2) * 5)
            contentWidth: width
            contentHeight: listColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: listColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.messages
                delegate: MessageRow {
                  required property var modelData
                  required property int index
                  width: listColumn.width
                  sender: TM.senderLabel(modelData.fromName, modelData.from)
                  subject: modelData.subject
                  age: TM.relativeTime(modelData.createdAt, root.now)
                  unread: !modelData.seen
                  hasAttachments: modelData.hasAttachments === true
                  selected: index === root.selectedIndex
                  foreground: panel.fg
                  fontFamily: panel.fontName
                  onHovered: root.selectedIndex = index
                  onClicked: root.openMessage(modelData)
                }
              }
            }
          }
        }

        // ---- Message view
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.current !== null

          Item {
            width: parent.width
            implicitHeight: backButton.implicitHeight

            Button {
              id: backButton
              anchors.left: parent.left
              text: "Inbox"
              iconText: "󰁍"
              foreground: panel.fg
              fontFamily: panel.fontName
              onClicked: root.current = null
            }
            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰆴"
              tooltipText: "Delete message"
              foreground: panel.fg
              fontFamily: panel.fontName
              onClicked: root.deleteMessage(root.current ? root.current.id : "")
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.current ? (root.current.subject || "(no subject)") : ""
            color: panel.fg
            font.family: panel.fontName
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.current
              ? TM.senderLabel(root.current.fromName, root.current.from)
                + (root.current.fromName ? " <" + root.current.from + ">" : "")
                + " · " + TM.relativeTime(root.current.createdAt, root.now)
              : ""
            color: Qt.darker(panel.fg, 1.4)
            font.family: panel.fontName
            font.pixelSize: Style.font.bodySmall
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.currentCodes.length > 0

            Repeater {
              model: root.currentCodes
              Button {
                required property var modelData
                text: "Copy code " + modelData
                iconText: "󰆏"
                foreground: panel.fg
                fontFamily: panel.fontName
                bordered: true
                onClicked: root.copy(modelData, "code")
              }
            }
          }

          Flickable {
            id: bodyFlick
            width: parent.width
            height: Math.min(bodyText.implicitHeight, Style.space(320))
            contentWidth: width
            contentHeight: bodyText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: bodyText
              width: bodyFlick.width
              // Escaped plain text with http(s) links only; see TM.linkify.
              textFormat: Text.StyledText
              wrapMode: Text.Wrap
              text: root.current
                ? (root.current.text ? TM.linkify(root.current.text) : (root.loadingMessage ? "Loading…" : "(empty message)"))
                : ""
              color: panel.fg
              linkColor: Color.accent
              font.family: panel.fontName
              font.pixelSize: Style.font.body
              onLinkActivated: function(link) {
                var url = TM.unescapeHtml(link)
                if (/^https?:\/\//i.test(url)) root.openUrl(url)
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: bodyText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
              }
            }
          }

          Text {
            visible: root.current !== null && root.current.attachments && root.current.attachments.length > 0
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: {
              if (!root.current || !root.current.attachments) return ""
              var names = []
              for (var i = 0; i < root.current.attachments.length; i++) names.push(root.current.attachments[i].filename)
              return "󰏢 " + names.join(", ") + " (open in browser to see them)"
            }
            color: Qt.darker(panel.fg, 1.4)
            font.family: panel.fontName
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            visible: root.current !== null && root.current.hasHtml === true
            text: "Open in browser"
            iconText: "󰖟"
            foreground: panel.fg
            fontFamily: panel.fontName
            bordered: true
            onClicked: root.run(["open", root.current.id], "ignore")
          }
        }

        // ---- Attribution (required by the mail.tm API terms)
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          textFormat: Text.StyledText
          text: 'Powered by <a href="https://mail.tm">mail.tm</a>'
          color: Qt.darker(panel.fg, 1.6)
          linkColor: Qt.darker(panel.fg, 1.2)
          font.family: panel.fontName
          font.pixelSize: Style.font.bodySmall
          onLinkActivated: function(link) { root.openUrl(link) }
        }
      }
    }
  }
}

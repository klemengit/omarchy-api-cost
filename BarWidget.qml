import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Icon-only bar pill; the popup is a cost dashboard with one tab per
// configured provider (summary, per-item breakdown sections). Data comes
// from api-cost.py, fetched on demand ("r") and when the popup opens onto
// a payload older than maxAgeSeconds. The last payload and the selected
// tab are cached on disk, so a reopen — including the first one after a
// shell restart — paints the previous numbers immediately and refreshes
// underneath. The script never raises, so a failing provider shows an
// error in its own tab instead of taking the bar down.
BarWidget {
  id: root
  moduleName: "io.github.klemengit.api-cost"

  readonly property string scriptPath: String(Qt.resolvedUrl("api-cost.py")).replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/api-cost"
  readonly property int maxAgeSeconds: setting("maxAgeSeconds", 300)

  property bool popupOpen: false
  property bool loading: false
  property bool everLoaded: false
  property string errorText: ""
  property var providers: []
  property string currentId: ""
  property real lastFetchMs: 0
  property bool stateLoaded: false

  readonly property var current: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].id === currentId) return providers[i]
    return providers.length > 0 ? providers[0] : null
  }
  readonly property bool currentOk: current !== null && current.ok === true
  readonly property string updatedLabel: current && current.updated
    ? Qt.formatDateTime(new Date(current.updated), "HH:mm") : ""

  // open/close/opened let `omarchy-shell shell toggle <id>` drive the popup.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }

  // `force` is the button and the "r" key; opening the popup passes nothing
  // and so only refetches once the cached payload has aged out.
  function refresh(force) {
    if (proc.running) return
    if (!force && lastFetchMs > 0 && Date.now() - lastFetchMs < maxAgeSeconds * 1000) return
    loading = true
    proc.running = true
  }

  function selectIndex(i) {
    if (providers.length === 0) return
    var n = providers.length
    currentId = providers[((i % n) + n) % n].id
  }

  function shiftTab(step) {
    for (var i = 0; i < providers.length; i++)
      if (providers[i] === current) return selectIndex(i + step)
  }

  function parse(raw) {
    loading = false
    everLoaded = true
    try {
      var data = JSON.parse(String(raw).trim())
      root.providers = data.providers || []
      root.errorText = data.error || ""
      root.lastFetchMs = Date.now()
      saveTimer.restart()
    } catch (e) {
      // Keep whatever is on screen; a torn read is not worth blanking the
      // panel for, and the next refresh overwrites it anyway.
      root.errorText = "Bad response from api-cost.py"
    }
  }

  // Hydrate from the cache written by the previous run, unless a fetch has
  // already landed. `updated` is the fetch time recorded by api-cost.py, so
  // it also decides whether the cache is still fresh enough to skip a fetch.
  function loadState(raw) {
    stateLoaded = true
    try {
      var data = JSON.parse(String(raw).trim())
      if (data.tab && currentId === "") root.currentId = data.tab
      if (everLoaded || !data.providers || data.providers.length === 0) return
      root.providers = data.providers
      root.errorText = data.error || ""
      var ms = Date.parse(data.updated || "")
      root.lastFetchMs = isNaN(ms) ? 0 : ms
    } catch (e) {
      // No cache yet, or an unreadable one: first open just fetches.
    }
  }

  function saveState() {
    // An empty payload carries nothing worth caching, and writing it would
    // drop the numbers the next startup wants to paint.
    if (!stateLoaded || providers.length === 0) return
    stateFile.setText(JSON.stringify({
      version: 1,
      tab: root.currentId,
      updated: new Date(root.lastFetchMs || Date.now()).toISOString(),
      error: root.errorText,
      providers: root.providers
    }) + "\n")
  }

  onPopupOpenChanged: if (popupOpen) refresh()
  onCurrentIdChanged: saveTimer.restart()

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  // Coalesces the writes that a fetch plus a tab switch would otherwise fire
  // back to back.
  Timer {
    id: saveTimer
    interval: 250
    onTriggered: root.saveState()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  Component.onCompleted: mkdirProc.running = true

  visible: true
  implicitWidth: pill.implicitWidth
  implicitHeight: barSize

  Process {
    id: proc
    command: ["bash", "-lc", "python3 '" + root.scriptPath + "'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.loading = false
        root.everLoaded = true
        root.errorText = "api-cost.py exited with code " + exitCode
      }
    }
  }

  WidgetButton {
    id: pill
    bar: root.bar
    text: String.fromCodePoint(0xF0D6)
    tooltipText: "API cost"
    fontSize: Style.font.body

    onPressed: function(button) { root.popupOpen = !root.popupOpen }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(flick.implicitHeight, Style.space(520))

    // Keyboard focus only reaches PopupWindow-based popups after a click/hover
    // routes it there, so a plain Keys.onPressed on the Flickable below isn't
    // reliable — KeyboardPanel primes real layer-shell keyboard focus instead,
    // and PanelKeyCatcher is the dispatcher that turns key events into
    // signals (r, Tab, h/l, digits here, plus Escape-to-close for free).
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.shiftTab(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.shiftTab(dx) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh(true)
        else if (t >= "1" && t <= "9" && Number(t) <= root.providers.length)
          root.selectIndex(Number(t) - 1)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        // Static gutter for the scrollbar, always reserved rather than
        // computed from the ScrollBar's own visible/width — those track
        // its fade animation, not layout, and left the cost column flush
        // against the edge while the bar was actually showing.
        anchors.rightMargin: Style.space(10)
        contentWidth: width
        contentHeight: column.implicitHeight
        readonly property real implicitHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

          // ---------- Header ----------
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: String.fromCodePoint(0xF0D6)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              width: parent.width - Style.space(66)
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: root.current ? root.current.name + " — Cost Dashboard" : "API Cost"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                visible: root.updatedLabel !== ""
                text: "Updated " + root.updatedLabel
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              iconText: String.fromCodePoint(0xF0450)
              iconSpinning: root.loading
              foreground: root.bar.foreground
              tooltipText: "Refresh (r)"
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.refresh(true)
            }
          }

          // ---------- Provider tabs ----------
          ButtonGroup {
            visible: root.providers.length > 1
            focusable: false
            options: root.providers.map(function(p, i) {
              return { value: p.id, label: p.name, tooltip: p.name + " (" + (i + 1) + ")" }
            })
            value: root.current ? root.current.id : ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(v) { root.currentId = v }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.currentOk
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.current && root.current.error ? root.current.error
              : root.errorText !== "" ? root.errorText
              : root.loading ? "Fetching…"
              : "No providers configured — see the README for the keys to set."
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- Summary ----------
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.currentOk

            Repeater {
              model: root.currentOk ? root.current.summary : []

              Row {
                required property var modelData
                width: parent.width

                Text {
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: Qt.darker(root.bar.foreground, modelData.primary ? 1.3 : 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: modelData.primary ? Style.font.body : Style.font.bodySmall
                  width: parent.width * 0.6
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.value
                  color: modelData.negative ? root.bar.urgent
                    : modelData.primary ? root.bar.foreground
                    : Qt.darker(root.bar.foreground, 1.2)
                  font.family: root.bar.fontFamily
                  font.pixelSize: modelData.primary ? Style.font.title : Style.font.bodySmall
                  font.bold: modelData.primary
                  width: parent.width * 0.4
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // ---------- Breakdown sections ----------
          Repeater {
            model: root.currentOk ? root.current.sections : []

            Column {
              required property var modelData
              width: column.width
              spacing: Style.space(10)

              PanelSeparator { foreground: root.bar.foreground }

              PanelSectionHeader {
                text: modelData.title
                foreground: root.bar.foreground
              }

              Column {
                width: parent.width
                spacing: Style.space(5)

                Repeater {
                  model: modelData.rows

                  Column {
                    required property var modelData
                    width: parent.width

                    Row {
                      width: parent.width
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width * 0.68
                        elide: Text.ElideRight
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.amount
                        color: modelData.negative ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.2)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width * 0.32
                        horizontalAlignment: Text.AlignRight
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: modelData.detail !== ""
                      text: modelData.detail
                      width: parent.width
                      elide: Text.ElideRight
                      color: Qt.darker(root.bar.foreground, 1.7)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

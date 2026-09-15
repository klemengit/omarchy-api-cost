import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar pill showing this month's net Scaleway spend. The popup IS the cost
// dashboard: summary, full per-resource breakdown, and recent invoices —
// no separate TUI/terminal needed. Data comes from scaleway-cost.py, polled
// on a timer and via on-demand refresh; the script never raises, so
// failures show here as an error pill/state instead of taking the bar down.
BarWidget {
  id: root
  moduleName: "io.github.klemengit.scaleway-cost"

  readonly property int refreshIntervalMs: Number(setting("refreshIntervalSec", 300)) * 1000

  property bool popupOpen: false
  property bool loading: false
  property bool ok: false
  property bool everLoaded: false
  property string errorText: ""
  property real net: 0
  property real beforeCredits: 0
  property real credit: 0
  property string currency: "EUR"
  property string symbol: "€"
  property var resources: []
  property var invoices: []
  property string updatedAt: ""

  readonly property string pillText: !everLoaded ? " …"
    : ok ? " " + symbol + net.toFixed(2)
    : " !"
  readonly property string updatedLabel: updatedAt !== ""
    ? Qt.formatDateTime(new Date(updatedAt), "HH:mm") : ""

  function close() { popupOpen = false }

  function refresh() {
    if (proc.running) return
    loading = true
    proc.running = true
  }

  function parse(raw) {
    loading = false
    everLoaded = true
    try {
      var data = JSON.parse(String(raw).trim())
      root.ok = data.ok === true
      root.errorText = data.error || ""
      root.net = typeof data.net === "number" ? data.net : 0
      root.beforeCredits = typeof data.beforeCredits === "number" ? data.beforeCredits : 0
      root.credit = typeof data.credit === "number" ? data.credit : 0
      root.currency = data.currency || "EUR"
      root.symbol = data.symbol || "€"
      root.resources = data.resources || []
      root.invoices = data.invoices || []
      root.updatedAt = data.updated || ""
    } catch (e) {
      root.ok = false
      root.errorText = "Bad response from scaleway-cost.py"
    }
  }

  visible: true
  implicitWidth: pill.implicitWidth
  implicitHeight: barSize

  Process {
    id: proc
    command: ["bash", "-lc", "python3 ~/.config/omarchy/plugins/io.github.klemengit.scaleway-cost/scaleway-cost.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.ok) {
        root.loading = false
        root.everLoaded = true
        root.errorText = "scaleway-cost.py exited with code " + exitCode
      }
    }
  }

  Timer {
    interval: Math.max(30000, root.refreshIntervalMs)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: pill
    bar: root.bar
    text: root.pillText
    tooltipText: root.ok ? "Scaleway — this month net: " + root.symbol + root.net.toFixed(2)
      : (root.errorText || "Scaleway cost")
    fontSize: Style.font.body

    onPressed: function(button) {
      if (button === Qt.RightButton) root.refresh()
      else root.popupOpen = !root.popupOpen
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(flick.implicitHeight, Style.space(520))

    Flickable {
      id: flick
      anchors.fill: parent
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
            text: ""
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
              text: "Scaleway — Cost Dashboard"
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
            iconText: ""
            iconSpinning: root.loading
            foreground: root.bar.foreground
            tooltipText: "Refresh"
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.refresh()
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.ok
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.errorText || "Fetching…"
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- Summary ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.ok

          Row {
            width: parent.width
            Text {
              textFormat: Text.PlainText
              text: "Total net spend"
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              width: parent.width * 0.6
            }
            Text {
              textFormat: Text.PlainText
              text: root.symbol + root.net.toFixed(2)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              width: parent.width * 0.4
              horizontalAlignment: Text.AlignRight
            }
          }

          Row {
            width: parent.width
            Text {
              textFormat: Text.PlainText
              text: "Before credits"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width * 0.6
            }
            Text {
              textFormat: Text.PlainText
              text: root.symbol + root.beforeCredits.toFixed(2)
              color: Qt.darker(root.bar.foreground, 1.2)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width * 0.4
              horizontalAlignment: Text.AlignRight
            }
          }

          Row {
            width: parent.width
            visible: root.credit !== 0
            Text {
              textFormat: Text.PlainText
              text: "Free tier credit"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width * 0.6
            }
            Text {
              textFormat: Text.PlainText
              text: root.symbol + root.credit.toFixed(2)
              color: root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width * 0.4
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        // ---------- Breakdown by resource ----------
        PanelSeparator {
          visible: root.ok && root.resources.length > 0
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: root.ok && root.resources.length > 0
          text: "Breakdown by resource"
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: root.ok && root.resources.length > 0

          Repeater {
            model: root.resources

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
                  text: root.symbol + Number(modelData.cost).toFixed(2)
                  color: Number(modelData.cost) < 0 ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.2)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: parent.width * 0.32
                  horizontalAlignment: Text.AlignRight
                }
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.category + " · " + modelData.qty + " " + modelData.unit
                color: Qt.darker(root.bar.foreground, 1.7)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---------- Recent invoices ----------
        PanelSeparator {
          visible: root.ok && root.invoices.length > 0
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: root.ok && root.invoices.length > 0
          text: "Recent invoices"
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.ok && root.invoices.length > 0

          Repeater {
            model: root.invoices

            Row {
              required property var modelData
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: modelData.period + "  ·  " + modelData.state
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: parent.width * 0.68
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
                text: root.symbol + Number(modelData.total).toFixed(2)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                width: parent.width * 0.32
                horizontalAlignment: Text.AlignRight
              }
            }
          }
        }
      }
    }
  }
}

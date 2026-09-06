import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: "evo.stocks"
  ipcTarget: "evo.stocks"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int chartHistoryDays: 30
  readonly property int chartBlockHeight: 112
  readonly property int refreshSeconds: 60

  property bool btcLoading: false
  property bool spcxLoading: false
  property var btcData: ({})
  property var spcxData: ({})

  readonly property var btc: Model.marketSection(btcData, "BTC", "https://www.tradingview.com/symbols/BTCUSD/", accent, chartHistoryDays)
  readonly property var spcx: Model.marketSection(spcxData, "SPCX", "https://app.trading212.com/", "#f9e2af", chartHistoryDays)

  readonly property bool iconActive: Model.hasPosition(btcData) || Model.hasPosition(spcxData)
  readonly property bool iconError: !btcLoading && btcData && btcData.ok === false
  readonly property bool iconBusy: loading && !(btcData && btcData.ok === true)
  readonly property bool iconMuted: false
  readonly property string barTooltip: Model.plain(Model.btcTooltip(btcData))

  readonly property string btcScript: Qt.resolvedUrl("bin/btc-status").toString().replace("file://", "")
  readonly property string spcxScript: Qt.resolvedUrl("bin/spcx-status").toString().replace("file://", "")

  readonly property bool loading: btcLoading || spcxLoading

  function applyBtcPayload(raw) {
    btcLoading = false
    var parsed = Model.parseMarketPayload(raw)
    if (parsed.ok) btcData = parsed
  }

  function applySpcxPayload(raw) {
    spcxLoading = false
    var parsed = Model.parseMarketPayload(raw)
    if (parsed.ok) spcxData = parsed
  }

  function refreshBtc() {
    if (!btcScript || btcProc.running) return
    btcLoading = true
    btcProc.command = ["bash", btcScript, String(chartHistoryDays)]
    btcProc.running = true
  }

  function refreshSpcx() {
    if (!spcxScript || spcxProc.running) return
    spcxLoading = true
    spcxProc.command = ["bash", spcxScript, String(chartHistoryDays)]
    spcxProc.running = true
  }

  function refresh() {
    refreshBtc()
    refreshSpcx()
  }

  function openMarketUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }

  function openFromHotkey() {
    root.controller.show()
    root.refresh()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: btcProc
    onStarted: { stdoutBuf = ""; stderrBuf = "" }

    property string stdoutBuf: ""
    property string stderrBuf: ""
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        btcProc.stdoutBuf += chunk
        if (btcProc.stdoutBuf.length > 262144) {
          btcProc.signal(15)
          btcProc.stdoutBuf = ""
        }
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        btcProc.stderrBuf += chunk
        if (btcProc.stderrBuf.length > 4096) {
          btcProc.signal(15)
          btcProc.stderrBuf = ""
        }
      }
    }
      onExited: function(exitCode) {
      var raw = String(stdoutBuf || "").trim()
        if (!raw) {
          root.btcLoading = false
          return
        }
        root.applyBtcPayload(raw)
    }
  }

  Process {
    id: spcxProc
    onStarted: { stdoutBuf = ""; stderrBuf = "" }

    property string stdoutBuf: ""
    property string stderrBuf: ""
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        spcxProc.stdoutBuf += chunk
        if (spcxProc.stdoutBuf.length > 262144) {
          spcxProc.signal(15)
          spcxProc.stdoutBuf = ""
        }
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        spcxProc.stderrBuf += chunk
        if (spcxProc.stderrBuf.length > 4096) {
          spcxProc.signal(15)
          spcxProc.stderrBuf = ""
        }
      }
    }
      onExited: function(exitCode) {
      var raw = String(stdoutBuf || "").trim()
        if (!raw) {
          root.spcxLoading = false
          return
        }
        root.applySpcxPayload(raw)
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }



  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.loading && !root.iconActive
            text: "Loading markets…"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          MarketSection {
            width: parent.width
            market: root.btc
            loading: root.btcLoading
          }

          MarketSection {
            width: parent.width
            market: root.spcx
            loading: root.spcxLoading
          }
        }
      }
    }
  }

  component MarketSection: Column {
    id: section
    property var market: ({})
    property bool loading: false
    spacing: Style.space(12)

    MouseArea {
      width: parent.width
      implicitHeight: marketHero.implicitHeight
      enabled: market.href !== ""
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openMarketUrl(market.href)

      PanelHero {
        id: marketHero
        width: parent.width
        title: market.name || "Market"
        meta: market.source || market.priceLabel || ""
        detail: section.loading ? "…" : (market.price || "")
        foreground: root.foreground
        fontFamily: root.fontFamily

        iconComponent: Component {
          Text {
            textFormat: Text.PlainText
            text: Model.marketSymbolIcon(market.name)
            color: market.chartColor || root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            opacity: 0.92
          }
        }
      }
    }

    GridLayout {
      width: parent.width
      columns: 4
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)

      Repeater {
        model: Model.marketStatBoxes(market, root.accent, root.urgent, root.foreground)

        StatBox {
          required property var modelData
          Layout.fillWidth: true
          value: String(modelData.value)
          label: modelData.label
          valueColor: modelData.valueColor !== undefined ? modelData.valueColor : root.accent
          special: modelData.special === true
          customFill: modelData.customFill === true
          foreground: root.foreground
          dim: root.dim
          fontFamily: root.fontFamily
        }
      }
    }

    Item {
      width: parent.width
      height: root.chartBlockHeight

      SparklineChart {
        anchors.fill: parent
        active: root.opened
        style: "candlestick"
        bullishColor: market.chartColor || root.accent
        bearishColor: root.urgent
        chartHeight: root.chartBlockHeight
        bars: market.bars || []
        showEmptyLabel: false
        fontFamily: root.fontFamily
        opacity: (market.bars || []).length > 0 ? 1 : 0.18

        Behavior on opacity {
          NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  component StatBox: BorderSurface {
    property string value: ""
    property string label: ""
    property color valueColor: foreground
    property bool special: false
    property bool customFill: false
    property color foreground: Color.foreground
    property color dim: Qt.darker(foreground, 1.4)
    property string fontFamily: Style.font.family

    implicitHeight: tileColumn.implicitHeight + Style.spacing.lg * 2
    color: customFill ? Qt.rgba(valueColor.r, valueColor.g, valueColor.b, 0.14) : Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
    radius: Style.cornerRadius

    Column {
      id: tileColumn
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      spacing: Style.spacing.labelGap

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: value
        color: special ? valueColor : foreground
        font.family: fontFamily
        font.pixelSize: special ? Style.font.title : Style.font.body
        font.bold: special
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: label
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}

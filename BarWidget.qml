import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// FX and crypto tickers. Crypto comes from CoinGecko's keyless /simple/price
// endpoint; FX from Frankfurter (ECB reference rates, updated each business
// day), fetched once against EUR so any pair can be crossed locally.
//
// Left click refreshes, scroll steps through tickers when rotating, and the
// tooltip carries full prices with 24h change.
BarWidget {
  id: root
  moduleName: "io.github.medden.prices"

  readonly property var cryptoIds: Model.cryptoIds(setting("crypto", "bitcoin,ethereum"))
  readonly property string vsCurrency: String(setting("vsCurrency", "usd")).toLowerCase()
  readonly property var fxPairs: Model.fxPairs(setting("fxPairs", "EUR/USD,GBP/USD"))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 5), 10) || 5)
  readonly property int rotateSeconds: Math.max(0, parseInt(setting("rotateSeconds", 0), 10) || 0)

  property var cryptoRows: []
  property var fxRows: []
  property int rotateIndex: 0
  property bool stale: false

  readonly property var rows: cryptoRows.concat(fxRows)
  readonly property string displayText: {
    if (rows.length === 0) return stale ? "prices ?" : ""
    if (rotateSeconds > 0) return Model.barText(rows[rotateIndex % rows.length])
    return rows.map(Model.barText).join("  ")
  }
  readonly property string tooltip: {
    var lines = rows.map(Model.tooltipLine)
    if (fxRows.length > 0 && fxRows[0].date) lines.push("FX as of " + fxRows[0].date + " (ECB)")
    if (stale) lines.push("Last refresh failed; showing previous values")
    return lines.join("\n")
  }

  function refresh() {
    stale = false
    if (cryptoIds.length > 0) {
      cryptoProc.command = ["curl", "-fsS", "--max-time", "10",
        "https://api.coingecko.com/api/v3/simple/price?ids=" + encodeURIComponent(cryptoIds.join(","))
        + "&vs_currencies=" + encodeURIComponent(vsCurrency) + "&include_24hr_change=true"]
      cryptoProc.running = true
    } else {
      cryptoRows = []
    }
    if (fxPairs.length > 0) {
      fxProc.running = true
    } else {
      fxRows = []
    }
  }

  function step(delta) {
    if (rows.length === 0) return
    rotateIndex = (rotateIndex + delta + rows.length) % rows.length
    if (rotateSeconds > 0) rotateTimer.restart()
  }

  onCryptoIdsChanged: Qt.callLater(refresh)
  onVsCurrencyChanged: Qt.callLater(refresh)
  onFxPairsChanged: Qt.callLater(refresh)

  visible: displayText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: cryptoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseCrypto(text, root.cryptoIds, root.vsCurrency)
        if (parsed && parsed.length > 0) root.cryptoRows = parsed
        else root.stale = true
      }
    }
  }

  Process {
    id: fxProc
    command: ["curl", "-fsS", "--max-time", "10", "https://api.frankfurter.dev/v1/latest?base=EUR"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseFx(text, root.fxPairs)
        if (parsed && parsed.length > 0) root.fxRows = parsed
        else root.stale = true
      }
    }
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: rotateTimer
    interval: Math.max(1, root.rotateSeconds) * 1000
    running: root.rotateSeconds > 0 && root.rows.length > 1
    repeat: true
    onTriggered: root.step(1)
  }

  IpcHandler {
    target: "io.github.medden.prices"

    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Price strings don't fit a vertical bar; show a glyph and keep the
    // numbers in the tooltip.
    text: root.vertical ? "$" : root.displayText
    tooltipText: root.tooltip
    horizontalMargin: 8.75

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.refresh()
    }
    onWheelMoved: function(delta) {
      if (root.rotateSeconds > 0) root.step(delta > 0 ? -1 : 1)
    }
  }
}

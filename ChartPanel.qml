import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Price chart popup. Ticker chips pick the series, range chips pick 24h or
// 7d; hovering the chart reads out the price at that moment. Histories are
// cached for five minutes so flicking between tickers doesn't hammer the
// free APIs.
Panel {
  id: root
  moduleName: "io.github.medden.prices"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget mounted in its slot, so the
  // popout coordinator and panel switching need the host widget, not us.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var rows: []
  property string vsCurrency: "usd"
  property int selectedIndex: 0
  property string range: "24h"

  property var points: []
  property bool loading: false
  property string error: ""
  property int hoverIndex: -1
  property var cache: ({})
  property string requestKey: ""

  readonly property var row: rows.length > 0 ? rows[Math.min(selectedIndex, rows.length - 1)] : null
  readonly property var stats: Model.chartStats(points)
  readonly property var hoverPoint: hoverIndex >= 0 && hoverIndex < points.length ? points[hoverIndex] : null
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dimmed: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function openOn(index) {
    if (index !== undefined && index >= 0) selectedIndex = index
    root.controller.show()
    load()
  }

  function close() {
    root.controller.hide()
  }

  function toggleOn(index) {
    if (root.opened) close()
    else openOn(index)
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function select(index) {
    if (rows.length === 0) return
    selectedIndex = (index + rows.length) % rows.length
    load()
  }

  function setRange(value) {
    if (value === range) return
    range = value
    load()
  }

  function load() {
    if (!row) return
    var key = row.label + "|" + range + "|" + vsCurrency
    var cached = cache[key]
    hoverIndex = -1
    error = ""
    if (cached && Date.now() - cached.at < 5 * 60 * 1000) {
      requestKey = key
      points = cached.points
      loading = false
      return
    }
    points = []
    loading = true
    requestKey = key
    chartProc.running = false
    chartProc.command = Model.chartCommand(row, range, vsCurrency, Math.floor(Date.now() / 1000))
    chartProc.key = key
    chartProc.kind = row.kind
    chartProc.running = true
  }

  onRowsChanged: if (selectedIndex >= rows.length) selectedIndex = 0
  onPointsChanged: chart.requestPaint()
  onHoverIndexChanged: chart.requestPaint()
  onForegroundChanged: chart.requestPaint()

  Process {
    id: chartProc
    property string key: ""
    property string kind: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A slower response for a ticker we've since left is dropped.
        if (chartProc.key !== root.requestKey) return
        var parsed = Model.parseChart(text, chartProc.kind)
        root.loading = false
        if (!parsed) {
          root.error = "Couldn't load chart data from " + (root.row ? Model.chartSource(root.row) : "the source")
          return
        }
        var next = Object.assign({}, root.cache)
        next[chartProc.key] = { at: Date.now(), points: parsed }
        root.cache = next
        root.points = parsed
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.select(root.selectedIndex + dx)
        else if (dy !== 0) root.setRange(Model.CHART_RANGES[(Model.CHART_RANGES.indexOf(root.range) + (dy > 0 ? 1 : Model.CHART_RANGES.length - 1)) % Model.CHART_RANGES.length])
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        // ---- Ticker and range pickers.
        Item {
          width: parent.width
          height: Math.max(tickerGroup.height, rangeGroup.height)

          ButtonGroup {
            id: tickerGroup
            anchors.left: parent.left
            focusable: false
            options: root.rows.map(function(r, i) { return { value: String(i), label: r.label } })
            value: String(root.selectedIndex)
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(v) { root.select(parseInt(v, 10)) }
          }

          ButtonGroup {
            id: rangeGroup
            anchors.right: parent.right
            focusable: false
            options: Model.CHART_RANGES
            value: root.range
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(v) { root.setRange(v) }
          }
        }

        // ---- Price read-out: hovered point, else latest.
        Row {
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            anchors.baseline: priceText.baseline
            text: root.row ? root.row.label : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            id: priceText
            textFormat: Text.PlainText
            text: root.hoverPoint ? Model.formatPrice(root.hoverPoint.v)
              : root.stats ? Model.formatPrice(root.stats.last) : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            anchors.baseline: priceText.baseline
            text: root.hoverPoint ? Model.formatChartTime(root.hoverPoint.t, root.range)
              : root.stats ? Model.formatChange(root.stats.change) + " " + root.range : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // ---- Chart.
        Item {
          width: parent.width
          height: Style.space(180)

          Canvas {
            id: chart
            anchors.fill: parent

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var pts = root.points
              var st = root.stats
              if (!pts || pts.length < 2 || !st) return

              var w = width
              var h = height
              var pad = 4
              var t0 = pts[0].t
              var span = Math.max(1, pts[pts.length - 1].t - t0)
              var lo = st.min
              var hi = st.max === st.min ? st.min + 1 : st.max
              function xAt(t) { return (t - t0) / span * w }
              function yAt(v) { return pad + (1 - (v - lo) / (hi - lo)) * (h - pad * 2) }

              var fg = root.foreground
              function rgba(a) {
                return "rgba(" + Math.round(fg.r * 255) + "," + Math.round(fg.g * 255) + "," + Math.round(fg.b * 255) + "," + a + ")"
              }

              // Opening-price reference line.
              ctx.strokeStyle = rgba(0.25)
              ctx.lineWidth = 1
              ctx.setLineDash([3, 4])
              ctx.beginPath()
              ctx.moveTo(0, Math.round(yAt(st.first)) + 0.5)
              ctx.lineTo(w, Math.round(yAt(st.first)) + 0.5)
              ctx.stroke()
              ctx.setLineDash([])

              ctx.beginPath()
              ctx.moveTo(xAt(pts[0].t), yAt(pts[0].v))
              for (var i = 1; i < pts.length; i++) ctx.lineTo(xAt(pts[i].t), yAt(pts[i].v))
              ctx.lineTo(w, h)
              ctx.lineTo(0, h)
              ctx.closePath()
              ctx.fillStyle = rgba(0.08)
              ctx.fill()

              ctx.beginPath()
              ctx.moveTo(xAt(pts[0].t), yAt(pts[0].v))
              for (var j = 1; j < pts.length; j++) ctx.lineTo(xAt(pts[j].t), yAt(pts[j].v))
              ctx.strokeStyle = rgba(1)
              ctx.lineWidth = 1.5
              ctx.lineJoin = "round"
              ctx.stroke()

              var hp = root.hoverPoint
              if (hp) {
                var hx = xAt(hp.t)
                ctx.strokeStyle = rgba(0.4)
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(Math.round(hx) + 0.5, 0)
                ctx.lineTo(Math.round(hx) + 0.5, h)
                ctx.stroke()
                ctx.fillStyle = rgba(1)
                ctx.beginPath()
                ctx.arc(hx, yAt(hp.v), 3.5, 0, Math.PI * 2)
                ctx.fill()
              }
            }
          }

          // High / low labels, top-left and bottom-left.
          Text {
            visible: root.stats !== null
            anchors.left: parent.left
            anchors.top: parent.top
            text: root.stats ? Model.formatPrice(root.stats.max) : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.stats !== null
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: root.stats ? Model.formatPrice(root.stats.min) : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.centerIn: parent
            visible: root.loading || root.error !== "" || (!root.loading && root.points.length === 0)
            text: root.loading ? "Loading…" : (root.error || "No data")
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: function(mouse) { root.hoverIndex = Model.nearestIndex(root.points, mouse.x, width) }
            onExited: root.hoverIndex = -1
          }
        }

        // ---- Time axis and source.
        Item {
          width: parent.width
          height: startLabel.implicitHeight

          Text {
            id: startLabel
            anchors.left: parent.left
            text: root.points.length > 0 ? Model.formatChartTime(root.points[0].t, root.range) : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              var note = Model.staleNote(root.points, Date.now())
              var source = root.row ? Model.chartSource(root.row) : ""
              return note ? note + " · " + source : source
            }
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            text: root.points.length > 0 ? Model.formatChartTime(root.points[root.points.length - 1].t, root.range) : ""
            color: root.dimmed
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

// Pure helpers for the prices widget, kept QML-free so they can be tested
// under node.

var SYMBOLS = {
  bitcoin: "BTC", ethereum: "ETH", solana: "SOL", ripple: "XRP", cardano: "ADA",
  dogecoin: "DOGE", tether: "USDT", "usd-coin": "USDC", binancecoin: "BNB",
  litecoin: "LTC", polkadot: "DOT", chainlink: "LINK", monero: "XMR", tron: "TRX"
}

function splitList(value) {
  return String(value || "").split(",")
    .map(function(s) { return s.replace(/^\s+|\s+$/g, "") })
    .filter(function(s) { return s !== "" })
}

function cryptoIds(value) {
  return splitList(value).map(function(s) { return s.toLowerCase() })
}

// "EUR/USD" or "EURUSD" -> { base: "EUR", quote: "USD" }; anything else is dropped.
function fxPairs(value) {
  var out = []
  splitList(value).forEach(function(s) {
    var m = s.toUpperCase().match(/^([A-Z]{3})\s*[\/\-]?\s*([A-Z]{3})$/)
    if (m) out.push({ base: m[1], quote: m[2] })
  })
  return out
}

function cryptoSymbol(id) {
  return SYMBOLS[id] || String(id).toUpperCase()
}

function formatPrice(value) {
  var n = Number(value)
  if (!isFinite(n)) return "?"
  if (n < 1) return n.toPrecision(4)
  var digits = n >= 1000 ? 0 : n >= 100 ? 2 : 4
  var fixed = n.toFixed(digits)
  if (n < 1000) return fixed
  return fixed.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function formatChange(pct) {
  var n = Number(pct)
  if (!isFinite(n)) return ""
  return (n >= 0 ? "▲" : "▼") + Math.abs(n).toFixed(2) + "%"
}

// CoinGecko /simple/price response -> ticker rows in the configured order.
function parseCrypto(raw, ids, vsCurrency) {
  var vs = String(vsCurrency || "usd").toLowerCase()
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  var rows = []
  ids.forEach(function(id) {
    var entry = data[id]
    if (!entry || entry[vs] === undefined) return
    rows.push({
      kind: "crypto",
      id: id,
      label: cryptoSymbol(id),
      price: entry[vs],
      change: entry[vs + "_24h_change"],
      quote: vs.toUpperCase()
    })
  })
  return rows
}

// Frankfurter /latest?base=EUR response -> cross rates for each pair.
function parseFx(raw, pairs) {
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || !data.rates) return null
  var rates = {}
  for (var k in data.rates) rates[k] = Number(data.rates[k])
  rates[data.base || "EUR"] = 1
  var rows = []
  pairs.forEach(function(p) {
    if (!rates[p.base] || !rates[p.quote]) return
    rows.push({ kind: "fx", base: p.base, quote: p.quote, label: p.base + "/" + p.quote, price: rates[p.quote] / rates[p.base], date: data.date || "" })
  })
  return rows
}

// ---- Live FX. Yahoo Finance first, ECB fixings as the fallback for any
// pair Yahoo doesn't answer.

function yahooSymbol(pair) {
  return pair.base + pair.quote + "=X"
}

// One curl for every pair: each response is one line of JSON, and a pair
// Yahoo rejects just prints nothing, so responses are matched by symbol.
function yahooQuoteCommand(pairs) {
  var argv = ["curl", "-sS", "-f", "--max-time", "10", "-A", "Mozilla/5.0", "-w", "\\n"]
  pairs.forEach(function(p) {
    argv.push("https://query1.finance.yahoo.com/v8/finance/chart/" + yahooSymbol(p) + "?range=1d&interval=1d")
  })
  return argv
}

// Yahoo chart responses, one per line -> { "EURUSD=X": { price, change, time } }.
function parseYahooQuotes(raw, fetchedAt) {
  var quotes = {}
  String(raw || "").split("\n").forEach(function(line) {
    if (line.replace(/\s+/g, "") === "") return
    try {
      var result = JSON.parse(line).chart.result[0]
      var meta = result.meta
      var price = Number(meta.regularMarketPrice)
      if (!meta.symbol || !isFinite(price) || price <= 0) return
      // Yahoo answers USD-based pairs under the short name: USDJPY=X comes
      // back as JPY=X.
      var symbol = String(meta.symbol).toUpperCase()
      if (/^[A-Z]{3}=X$/.test(symbol)) symbol = "USD" + symbol
      quotes[symbol] = {
        price: price,
        change: meta.regularMarketChangePercent,
        time: Number(meta.regularMarketTime) * 1000,
        fetchedAt: fetchedAt
      }
    } catch (e) {}
  })
  return quotes
}

// Configured pairs -> bar rows: a Yahoo quote fetched within `maxAgeMs` wins,
// otherwise the ECB row for the pair, otherwise the pair is left out.
function mergeFx(pairs, yahooQuotes, ecbRows, nowMs, maxAgeMs) {
  var ecb = {}
  ;(ecbRows || []).forEach(function(r) { ecb[r.label] = r })
  var rows = []
  pairs.forEach(function(p) {
    var label = p.base + "/" + p.quote
    var q = yahooQuotes ? yahooQuotes[yahooSymbol(p)] : null
    if (q && nowMs - q.fetchedAt <= maxAgeMs) {
      rows.push({ kind: "fx", base: p.base, quote: p.quote, label: label, price: q.price,
        changeDay: q.change, source: "Yahoo", time: q.time })
    } else if (ecb[label]) {
      var r = ecb[label]
      rows.push({ kind: "fx", base: p.base, quote: p.quote, label: label, price: r.price,
        source: "ECB", date: r.date })
    }
  })
  return rows
}

function barText(row) {
  return row.label + " " + formatPrice(row.price)
}

function tooltipLine(row) {
  var line = row.label + "  " + formatPrice(row.price)
  if (row.kind === "crypto") line += " " + row.quote
  var change = formatChange(row.change)
  if (change) line += "  " + change + " 24h"
  var dayChange = formatChange(row.changeDay)
  if (dayChange) line += "  " + dayChange + " day"
  if (row.source === "Yahoo" && row.time) {
    line += "  (Yahoo " + shortStamp(row.time, Date.now()) + ")"
  } else if (row.source === "ECB") {
    line += "  (ECB " + row.date + ")"
  }
  return line
}

// ---- Charts. Crypto history comes from CoinGecko's market_chart; FX from
// Yahoo Finance's chart endpoint, since Frankfurter only has daily fixings.

var CHART_RANGES = ["24h", "7d"]

// curl argv for a ticker's price history over `range`.
function chartCommand(row, range, vsCurrency, nowSeconds) {
  if (row.kind === "crypto") {
    return ["curl", "-fsS", "--max-time", "10",
      "https://api.coingecko.com/api/v3/coins/" + encodeURIComponent(row.id)
      + "/market_chart?vs_currency=" + encodeURIComponent(String(vsCurrency || "usd").toLowerCase())
      + "&days=" + (range === "7d" ? "7" : "1")]
  }
  // Yahoo rejects requests without a browser-like user agent. range=1d is
  // the latest trading session, so weekends still show Friday.
  var query = range === "7d"
    ? "period1=" + (nowSeconds - 7 * 86400) + "&period2=" + nowSeconds + "&interval=30m"
    : "range=1d&interval=5m"
  return ["curl", "-fsS", "--max-time", "10", "-A", "Mozilla/5.0",
    "https://query1.finance.yahoo.com/v8/finance/chart/" + row.base + row.quote + "=X?" + query]
}

// Either response -> [{ t: epoch ms, v: price }], oldest first, gaps dropped.
function parseChart(raw, kind) {
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  var points = []
  if (kind === "crypto") {
    var prices = data && data.prices
    if (!prices || !prices.length) return null
    prices.forEach(function(p) {
      if (p && isFinite(Number(p[1]))) points.push({ t: Number(p[0]), v: Number(p[1]) })
    })
  } else {
    var result = data && data.chart && data.chart.result && data.chart.result[0]
    var times = result && result.timestamp
    var closes = result && result.indicators && result.indicators.quote
      && result.indicators.quote[0] && result.indicators.quote[0].close
    if (!times || !closes) return null
    for (var i = 0; i < times.length; i++) {
      if (closes[i] !== null && closes[i] !== undefined && isFinite(Number(closes[i])))
        points.push({ t: times[i] * 1000, v: Number(closes[i]) })
    }
  }
  return points.length > 1 ? points : null
}

function chartStats(points) {
  if (!points || points.length === 0) return null
  var min = points[0].v
  var max = points[0].v
  points.forEach(function(p) {
    if (p.v < min) min = p.v
    if (p.v > max) max = p.v
  })
  var first = points[0].v
  var last = points[points.length - 1].v
  return { first: first, last: last, min: min, max: max, change: first ? (last / first - 1) * 100 : 0 }
}

// Index of the point closest to x across a chart `width` pixels wide.
function nearestIndex(points, x, width) {
  if (!points || points.length === 0 || width <= 0) return -1
  var t0 = points[0].t
  var span = points[points.length - 1].t - t0
  var target = t0 + Math.max(0, Math.min(1, x / width)) * span
  var best = 0
  for (var i = 1; i < points.length; i++) {
    if (Math.abs(points[i].t - target) < Math.abs(points[best].t - target)) best = i
  }
  return best
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

// "14:05" for today, "Fri 16 21:55" for anything older.
function shortStamp(ms, nowMs) {
  var d = new Date(ms)
  var time = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (new Date(nowMs).toDateString() === d.toDateString()) return time
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[d.getDay()] + " " + d.getDate() + " " + time
}

function formatChartTime(ms, range) {
  var d = new Date(ms)
  var time = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (range !== "7d") return time
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[d.getDay()] + " " + d.getDate() + " " + time
}

// FX charts can end hours before now (weekends, holidays); say which
// session the chart shows rather than implying it is live.
function staleNote(points, nowMs) {
  if (!points || points.length === 0) return ""
  var last = points[points.length - 1].t
  if (nowMs - last < 3 * 60 * 60 * 1000) return ""
  var d = new Date(last)
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return "Market closed · data to " + days[d.getDay()] + " " + d.getDate() + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function chartSource(row) {
  return row.kind === "crypto" ? "CoinGecko" : "Yahoo Finance"
}

if (typeof module !== "undefined") {
  module.exports = {
    splitList: splitList,
    cryptoIds: cryptoIds,
    fxPairs: fxPairs,
    cryptoSymbol: cryptoSymbol,
    formatPrice: formatPrice,
    formatChange: formatChange,
    parseCrypto: parseCrypto,
    parseFx: parseFx,
    yahooSymbol: yahooSymbol,
    yahooQuoteCommand: yahooQuoteCommand,
    parseYahooQuotes: parseYahooQuotes,
    mergeFx: mergeFx,
    barText: barText,
    CHART_RANGES: CHART_RANGES,
    chartCommand: chartCommand,
    parseChart: parseChart,
    chartStats: chartStats,
    nearestIndex: nearestIndex,
    formatChartTime: formatChartTime,
    staleNote: staleNote,
    chartSource: chartSource,
    tooltipLine: tooltipLine
  }
}

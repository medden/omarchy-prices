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
  var digits = n >= 1000 ? 0 : n >= 100 ? 2 : n >= 1 ? 4 : 6
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
    rows.push({ label: p.base + "/" + p.quote, price: rates[p.quote] / rates[p.base], date: data.date || "" })
  })
  return rows
}

function barText(row) {
  return row.label + " " + formatPrice(row.price)
}

function tooltipLine(row) {
  var line = row.label + "  " + formatPrice(row.price)
  if (row.quote) line += " " + row.quote
  var change = formatChange(row.change)
  if (change) line += "  " + change + " 24h"
  return line
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
    barText: barText,
    tooltipLine: tooltipLine
  }
}

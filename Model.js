.pragma library

// Pure helpers for the aircap panel: channel plans and formatting.

var BANDS = [
  { value: "2.4", label: "2.4 GHz" },
  { value: "5", label: "5 GHz" },
  { value: "6", label: "6 GHz" }
]

function parseStatus(raw) {
  try {
    var parsed = JSON.parse(String(raw || "").trim())
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (e) {
    return null
  }
}

function bandOf(freq) {
  if (freq < 2500) return "2.4"
  if (freq < 5950) return "5"
  return "6"
}

function chanFreq(band, ch) {
  if (band === "2.4") return ch === 14 ? 2484 : 2407 + 5 * ch
  if (band === "5") return 5000 + 5 * ch
  return 5950 + 5 * ch
}

function bandsAvailable(channels) {
  var out = []
  for (var i = 0; i < BANDS.length; i++) {
    for (var j = 0; j < channels.length; j++) {
      if (bandOf(channels[j].freq) === BANDS[i].value) { out.push(BANDS[i]); break }
    }
  }
  return out
}

function bandChannels(channels, band) {
  return channels.filter(function(c) { return bandOf(c.freq) === band })
}

function findChannel(channels, freq) {
  for (var i = 0; i < channels.length; i++) if (channels[i].freq === freq) return channels[i]
  return null
}

// 6 GHz preferred scanning channels: 5, 21, 37, … (every fourth 20 MHz).
function isPsc(c) {
  return bandOf(c.freq) === "6" && (c.ch - 5) % 16 === 0
}

// Standard 802.11 bonding blocks. 5 GHz counts from 36 below UNII-3 and from
// 149 above it; 6 GHz counts from channel 1. 320 MHz uses the 320-1 set.
function block(band, ch, width) {
  var n = width / 5
  var start = band === "6" ? 1 : (ch >= 149 ? 149 : 36)
  var first = start + Math.floor((ch - start) / n) * n
  var members = []
  for (var c = first; c < first + n; c += 4) members.push(c)
  return { centerCh: first + n / 2 - 2, members: members }
}

// Width choices for one channel, each with the center frequency iw needs.
// A width is offered only if every 20 MHz subchannel is enabled.
function widthOptions(channels, freq) {
  var enabled = {}
  for (var i = 0; i < channels.length; i++) enabled[channels[i].freq] = true
  var c = findChannel(channels, freq)
  if (!c) return []
  var band = bandOf(freq)
  var out = [{ value: "20", label: "20", width: 20, center: freq }]

  if (band === "2.4") {
    if (enabled[freq + 20]) out.push({ value: "40+", label: "40+", width: 40, center: freq + 10, tooltip: "HT40+ · secondary above" })
    if (enabled[freq - 20]) out.push({ value: "40-", label: "40−", width: 40, center: freq - 10, tooltip: "HT40− · secondary below" })
    return out
  }

  var widths = band === "6" ? [40, 80, 160, 320] : [40, 80, 160]
  for (var w = 0; w < widths.length; w++) {
    var b = block(band, c.ch, widths[w])
    var ok = b.members.every(function(m) { return enabled[chanFreq(band, m)] })
    if (ok) out.push({ value: String(widths[w]), label: String(widths[w]), width: widths[w], center: chanFreq(band, b.centerCh) })
  }
  return out
}

function findWidth(options, value) {
  for (var i = 0; i < options.length; i++) if (options[i].value === value) return options[i]
  return null
}

// The width option matching a known (width, center) pair, e.g. the current
// association or the last capture.
function widthValueFor(options, width, center) {
  for (var i = 0; i < options.length; i++) {
    if (options[i].width === width && (width === 20 || options[i].center === center)) return options[i].value
  }
  return options.length ? options[options.length - 1].value : "20"
}

function bandPrefix(freq) {
  var b = bandOf(freq)
  return b === "2.4" ? "2g" : b + "g"
}

// "5g-ch36-80MHz": used in file names.
function fileLabel(c, width) {
  return bandPrefix(c.freq) + "-ch" + c.ch + "-" + width + "MHz"
}

function tuningText(c, opt) {
  if (!c || !opt) return ""
  return "Ch " + c.ch + " · " + opt.label.replace("−", "-") + " MHz · " + c.freq + " MHz" + (opt.width > 20 ? " (center " + opt.center + ")" : "")
}

function groupDigits(n) {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function compactCount(n) {
  if (n < 1000) return String(n)
  if (n < 10000) return (n / 1000).toFixed(1) + "k"
  if (n < 1000000) return Math.round(n / 1000) + "k"
  return (n / 1000000).toFixed(1) + "M"
}

function bytesText(n) {
  if (!(n > 0)) return "0 B"
  var units = ["B", "KB", "MB", "GB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + units[i]
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function elapsedText(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  var h = Math.floor(seconds / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  var s = seconds % 60
  return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(s)
}

function whenText(epochSeconds) {
  var d = new Date(epochSeconds * 1000)
  var now = new Date()
  var time = pad(d.getHours()) + ":" + pad(d.getMinutes())
  if (d.toDateString() === now.toDateString()) return time
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) + " " + time
}

// ── Scan data ────────────────────────────────────────────────────────────
// `scan` is NetworkManager's cached BSS list: {freq, width, signal, bssid,
// ssid}. A BSSID counts on its primary channel only: that's where its
// beacons are, so it's the channel guaranteed to have traffic.

// Per channel (keyed by freq): {count, ssids}.
function scanByChannel(channels, scan) {
  var out = {}
  for (var i = 0; i < channels.length; i++) out[channels[i].freq] = { count: 0, ssids: {} }
  if (!scan) return out
  for (var j = 0; j < scan.length; j++) {
    var entry = out[scan[j].freq]
    if (!entry) continue
    entry.count += 1
    if (scan[j].ssid) entry.ssids[scan[j].ssid] = true
  }
  return out
}

function bandCount(summary, band) {
  var n = 0
  for (var f in summary) if (bandOf(Number(f)) === band) n += summary[f].count
  return n
}

function bssidsText(n) {
  return n === 1 ? "1 BSSID" : n + " BSSIDs"
}

// "8 BSSIDs (7 networks) on this channel"
function scanDetail(summary, freq) {
  var s = summary[freq]
  if (!s) return ""
  if (s.count === 0) return "No BSSIDs on this channel in the last scan · capture may be nearly empty"
  var ssids = Object.keys(s.ssids).length
  return bssidsText(s.count) + (ssids > 0 && ssids !== s.count ? " (" + ssids + " network" + (ssids === 1 ? "" : "s") + ")" : "") + " on this channel"
}

// Rows for ChannelDropdown. With hideEmpty, channels without BSSIDs are
// dropped, except `keepFreq` (the current selection).
function channelRows(list, summary, hideEmpty, keepFreq) {
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    var count = summary[c.freq] ? summary[c.freq].count : 0
    if (hideEmpty && count === 0 && c.freq !== keepFreq) continue
    var tags = []
    if (c.radar) tags.push("DFS")
    if (isPsc(c)) tags.push("PSC")
    rows.push({ value: String(c.freq), ch: c.ch, freq: c.freq, tags: tags.join(" "), count: count })
  }
  return rows
}

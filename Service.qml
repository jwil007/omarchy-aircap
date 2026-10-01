import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless capture state. Radio/setup status comes from `aircap status`;
// a running capture is a child process whose stderr carries the helper's
// "aircap: key=value" lines and dumpcap's packet counter.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  readonly property string toolPath: String(Qt.resolvedUrl("bin/aircap")).replace(/^file:\/\//, "")
  readonly property string configuredIface: String(setting("iface", "") || "").trim()
  readonly property string captureDir: String(setting("captureDir", "") || "").trim() || "~/Captures"
  readonly property int snapLength: Math.max(0, parseInt(String(setting("snapLength", 0)), 10) || 0)
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aircap"

  // Radio + setup status
  property bool statusKnown: false
  property string iface: configuredIface
  property string ifaceType: ""
  property string ssid: ""
  property var current: null
  property var channels: []
  property bool dumpcapInstalled: false
  property bool wiresharkInstalled: false
  property bool helperInstalled: false
  property bool setupCurrent: false
  property var captures: []
  property var lastTuning: null
  readonly property bool ready: dumpcapInstalled && setupCurrent && iface !== ""
  // Left in monitor mode with nothing capturing: a capture died uncleanly.
  readonly property bool stranded: statusKnown && ifaceType === "monitor" && !capturing

  // Selection
  property string band: "5"
  property int freq: 0
  property string widthValue: "20"
  property bool selectionInitialized: false
  readonly property var bands: Model.bandsAvailable(channels)
  readonly property var bandChannelList: Model.bandChannels(channels, band)
  readonly property var channel: Model.findChannel(channels, freq)
  readonly property var widthOptions: Model.widthOptions(channels, freq)
  readonly property var widthOption: Model.findWidth(widthOptions, widthValue)
  readonly property bool canStart: ready && !capturing && channel !== null && widthOption !== null

  // Preferences (persisted in stateDir/prefs.json)
  property bool openWhenDone: setting("openInWireshark", true) === true

  // Capture state. A capture can also be "detached": still running after a
  // shell restart dropped our child process. Those can be stopped but have
  // no live counter.
  readonly property bool ownCapture: captureProcess.running
  property bool detachedCapture: false
  readonly property bool capturing: ownCapture || detachedCapture
  property string phase: ""          // configuring / capturing / restoring
  property bool stopping: false
  property int packets: 0
  property int dropped: -1
  property double startedAt: 0
  property string file: ""
  property string tuning: ""
  property real fileSize: 0
  property double now: Date.now()
  property string lastError: ""
  property string _captureError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function notify(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "--app-name=aircap", "--transient",
      "--urgency=" + (urgency || "low"),
      "--hint=string:omarchy-glyph:\u{f1673}", title, body || ""])
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [toolPath, "status", configuredIface, captureDir]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var s = Model.parseStatus(raw)
    if (!s) return
    statusKnown = true
    iface = String(s.iface || "")
    ifaceType = String(s.type || "")
    ssid = String(s.ssid || "")
    current = s.current || null
    if (JSON.stringify(s.channels || []) !== JSON.stringify(channels)) channels = s.channels || []
    dumpcapInstalled = s.dumpcap === true
    wiresharkInstalled = s.wireshark === true
    helperInstalled = s.helperInstalled === true
    setupCurrent = s.setupCurrent === true
    captures = s.captures || []
    lastTuning = s.last || null

    detachedCapture = !ownCapture && s.capturing === true
    if (detachedCapture && s.activeCapture) {
      file = String(s.activeCapture.file || "")
      tuning = String(s.activeCapture.label || "")
      startedAt = Number(s.activeCapture.startedAt || 0) * 1000
    }
    if (!s.capturing && !ownCapture) stopping = false
    if (!selectionInitialized && channels.length > 0) initSelection()
  }

  // Start from the last capture's tuning, else the current association,
  // else 5 GHz channel 36.
  function initSelection() {
    selectionInitialized = true
    var pick = lastTuning && Model.findChannel(channels, lastTuning.freq) ? lastTuning
      : current && Model.findChannel(channels, current.freq) ? current
      : null
    if (pick) selectTuning(pick.freq, pick.width, pick.center)
    else selectBand(Model.findChannel(channels, 5180) ? "5" : (bands.length ? bands[0].value : "2.4"))
  }

  function selectTuning(f, width, center) {
    band = Model.bandOf(f)
    freq = f
    widthValue = Model.widthValueFor(Model.widthOptions(channels, f), width, center)
  }

  function useCurrentChannel() {
    if (current && !capturing) selectTuning(current.freq, current.width, current.center)
  }

  function selectBand(b) {
    if (capturing) return
    band = b
    var list = Model.bandChannels(channels, b)
    if (list.length === 0) return
    if (Model.bandOf(freq) !== b) {
      var preferred = b === "2.4" ? 2437 : b === "5" ? 5180 : 5975 // ch 6 / 36 / 5 (PSC)
      selectChannel(Model.findChannel(list, preferred) ? preferred : list[0].freq)
    }
  }

  // Keep the chosen width when the new channel supports it, else the widest.
  function selectChannel(f) {
    if (capturing) return
    freq = f
    var opts = Model.widthOptions(channels, f)
    if (!Model.findWidth(opts, widthValue)) {
      var keep = widthValue === "40+" || widthValue === "40-" ? "40" : widthValue
      widthValue = Model.findWidth(opts, keep) ? keep : (opts.length ? opts[opts.length - 1].value : "20")
    }
  }

  function selectWidth(v) {
    if (!capturing) widthValue = v
  }

  function setOpenWhenDone(on) {
    openWhenDone = on
    prefsView.setText(JSON.stringify({ openWhenDone: on }) + "\n")
  }

  function start() {
    if (!canStart) return
    var opt = widthOption
    lastError = ""
    _captureError = ""
    packets = 0
    dropped = -1
    fileSize = 0
    file = ""
    phase = "configuring"
    stopping = false
    startedAt = Date.now()
    tuning = Model.tuningText(channel, opt)
    captureProcess.command = [toolPath, "capture", iface, String(freq), String(opt.width), String(opt.center),
      String(snapLength), captureDir, Model.fileLabel(channel, opt.width)]
    captureProcess.running = true
  }

  function stop() {
    if (!capturing || stopProcess.running) return
    stopping = true
    phase = "restoring"
    stopProcess.command = [toolPath, "stop", iface]
    stopProcess.running = true
  }

  function toggle() {
    if (capturing) stop()
    else start()
  }

  function restore() {
    if (stopProcess.running) return
    lastError = ""
    stopProcess.command = [toolPath, "restore", iface]
    stopProcess.running = true
  }

  function setup() { Quickshell.execDetached([toolPath, "setup"]) }
  function openCapture(path) { if (path) Quickshell.execDetached([toolPath, "open", path]) }
  function revealCapture(path) { if (path) Quickshell.execDetached([toolPath, "reveal", path]) }
  function openFolder() {
    var dir = captureDir.replace(/^~/, Quickshell.env("HOME"))
    Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && exec uwsm-app -- nautilus \"$1\"", "sh", dir])
  }

  function handleLine(line) {
    var m
    if ((m = /Packets: (\d+)/.exec(line))) packets = parseInt(m[1], 10)
    else if ((m = /^Packets captured: (\d+)/.exec(line))) packets = parseInt(m[1], 10)
    else if ((m = /^Packets received\/dropped on interface .*: (\d+)\/(\d+)/.exec(line))) {
      packets = parseInt(m[1], 10)
      dropped = parseInt(m[2], 10)
    }
    else if ((m = /^aircap: file=(.*)$/.exec(line))) file = m[1]
    else if ((m = /^aircap: state=(\w+)/.exec(line))) {
      phase = m[1]
      if (phase === "capturing") startedAt = Date.now()
    }
    else if ((m = /^aircap: error=(.*)$/.exec(line))) _captureError = m[1]
    else if ((m = /^aircap: (.*)$/.exec(line))) _captureError = m[1]
    else if (/^(sudo|dumpcap): /.test(line) && !/^dumpcap: Running as user/.test(line)) _captureError = line
  }

  function finishCapture(exitCode) {
    var saved = file !== "" && exitCode === 0 && packets > 0
    var path = file
    phase = ""
    stopping = false
    if (exitCode !== 0) {
      lastError = _captureError || "Capture failed (exit " + exitCode + ")"
      notify("Capture failed", lastError, "normal")
    } else if (!saved) {
      lastError = "No packets captured"
      notify("Capture stopped", "No packets were captured on " + tuning)
    } else {
      notify("Capture saved", Model.groupDigits(packets) + " packets · " + tuning + "\n" + path)
      if (openWhenDone) openCapture(path)
    }
    refresh()
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

  FileView {
    id: prefsView
    path: root.stateDir + "/prefs.json"
    printErrors: false
    onLoaded: {
      var p = Model.parseStatus(text())
      if (p && typeof p.openWhenDone === "boolean") root.openWhenDone = p.openWhenDone
    }
  }

  Process {
    id: captureProcess
    stderr: SplitParser {
      onRead: function(line) { root.handleLine(String(line)) }
    }
    onExited: function(exitCode) { root.finishCapture(exitCode) }
  }

  Process {
    id: stopProcess
    stderr: StdioCollector {
      id: stopErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.stopping = false
        var message = String(stopErr.text || "").trim()
        root.lastError = message !== "" ? message.split("\n").pop().replace(/^aircap: (error=)?/, "") : "Stop failed"
      }
      root.refresh()
    }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
    }
  }

  Process {
    id: sizeProcess
    stdout: StdioCollector {
      id: sizeOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var n = parseFloat(String(sizeOut.text || "").trim())
      if (exitCode === 0 && isFinite(n)) root.fileSize = n
    }
  }

  // Elapsed time and file size while capturing.
  Timer {
    interval: 1000
    repeat: true
    running: root.capturing
    triggeredOnStart: true
    onTriggered: {
      root.now = Date.now()
      if (root.file !== "" && !sizeProcess.running) {
        sizeProcess.command = ["stat", "-c", "%s", root.file]
        sizeProcess.running = true
      }
    }
  }

  Timer {
    interval: root.panelOpen || root.capturing ? 3000 : 20000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}

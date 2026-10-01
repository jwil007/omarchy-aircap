import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jwil007.aircap"
  ipcTarget: "jwil007.aircap"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphIdle: "\u{f1674}"     // shark-fin-outline
  readonly property string glyphActive: "\u{f1673}"   // shark-fin
  readonly property double elapsed: cap.capturing && cap.startedAt > 0 ? (cap.now - cap.startedAt) / 1000 : 0
  readonly property var lastCapture: cap.captures.length > 0 ? cap.captures[0] : null

  readonly property string detail: {
    if (cap.capturing) {
      if (cap.phase === "resetting") return "Resetting radio…"
      return cap.stopping ? "Stopping…" : cap.phase === "configuring" ? "Tuning…" : "Capturing"
    }
    if (cap.stranded) return "Monitor mode"
    if (!cap.statusKnown) return ""
    return cap.ready ? "Ready" : "Setup needed"
  }

  readonly property string heroMeta: {
    if (!cap.statusKnown) return "Checking…"
    if (cap.iface === "") return "No wireless interface found"
    if (cap.capturing) return cap.iface + " · " + (cap.tuning || "monitor mode")
    if (cap.stranded) return cap.iface + " was left in monitor mode"
    if (cap.ssid !== "" && cap.current) {
      var c = Model.findChannel(cap.channels, cap.current.freq)
      return cap.ssid + " · ch " + (c ? c.ch : cap.current.freq) + " · " + cap.current.width + " MHz"
    }
    return cap.iface + " · not associated"
  }

  readonly property string tooltip: {
    if (cap.capturing) return "aircap · capturing " + cap.tuning + (cap.ownCapture ? " · " + Model.groupDigits(cap.packets) + " packets" : "")
    if (cap.stranded) return "aircap · " + cap.iface + " stuck in monitor mode (click to restore)"
    return "aircap · " + (cap.ready ? "ready" : "setup needed")
  }

  function run(action) {
    if (action === "toggle") cap.toggle()
    else if (action === "setup") { cap.setup(); root.close() }
    else if (action === "restore") cap.restore()
    else if (action === "current") cap.useCurrentChannel()
    else if (action === "last" && root.lastCapture) { cap.openCapture(root.lastCapture.path); root.close() }
    else if (action === "folder") { cap.openFolder(); root.close() }
  }

  implicitWidth: cap.capturing ? liveButton.implicitWidth : idleButton.implicitWidth
  implicitHeight: cap.capturing ? liveButton.implicitHeight : idleButton.implicitHeight

  onOpenedChanged: if (opened) {
    cap.refresh()
    cap.rescanIfStale()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: cap
    settings: root.settings
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): void { cap.start() }
    function stop(): void { cap.stop() }
    function toggleCapture(): void { cap.toggle() }
    function restore(): void { cap.restore() }
    function resetRadio(): void { cap.resetRadio() }
    function rescan(): void { cap.rescan() }
    function status(): string { return root.tooltip }
  }

  function onBarPressed(buttonCode) {
    if (buttonCode === Qt.MiddleButton && root.lastCapture) cap.openCapture(root.lastCapture.path)
    else if (buttonCode === Qt.RightButton) cap.capturing ? cap.stop() : cap.start()
    else root.toggle()
  }

  BarIconButton {
    id: idleButton
    anchors.fill: parent
    visible: !cap.capturing
    bar: root.bar
    text: root.glyphIdle
    active: cap.stranded
    dimmed: cap.statusKnown && !cap.ready
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.onBarPressed(buttonCode) }
  }

  WidgetButton {
    id: liveButton
    anchors.fill: parent
    visible: cap.capturing
    bar: root.bar
    active: true
    text: root.glyphActive + " " + (cap.ownCapture ? Model.compactCount(cap.packets) : Model.elapsedText(root.elapsed))
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.onBarPressed(buttonCode) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: cap.capturing ? liveButton : idleButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: {
        if (cap.stranded) root.run("restore")
        else if (cap.statusKnown && !cap.ready && !cap.capturing) root.run("setup")
        else root.run("toggle")
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "c") root.run("current")
        else if (key === "w") root.run("last")
        else if (key === "f") root.run("folder")
        else if (key === "1" || key === "2") cap.selectBand("2.4")
        else if (key === "5") cap.selectBand("5")
        else if (key === "6") cap.selectBand("6")
        else if (key === "r") cap.rescan()
        else if (key === "h") cap.setHideEmpty(!cap.hideEmpty)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: vbar; policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width - (panelFlick.interactive ? vbar.width + Style.space(4) : 0)
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "aircap"
            detail: root.detail
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                id: heroGlyph
                text: cap.capturing ? root.glyphActive : root.glyphIdle
                color: cap.capturing || cap.stranded ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display

                SequentialAnimation on opacity {
                  running: cap.capturing
                  loops: Animation.Infinite
                  onRunningChanged: if (!running) heroGlyph.opacity = 1
                  NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          Text {
            visible: cap.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: cap.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            visible: cap.stranded
            width: parent.width
            glyph: "\u{f05a9}"
            title: "Restore Wi-Fi"
            subtitle: "Switch " + cap.iface + " back to managed mode and reconnect"
            onActivated: root.run("restore")
          }

          ActionRow {
            visible: cap.statusKnown && cap.iface !== "" && !cap.ready && !cap.capturing
            width: parent.width
            glyph: ""
            title: cap.helperInstalled && cap.dumpcapInstalled ? "Update capture helper" : "Set up monitor-mode capture"
            subtitle: cap.helperInstalled && cap.dumpcapInstalled
              ? "One-time sudo: the plugin's helper changed"
              : (cap.wiresharkInstalled ? "One-time sudo: installs a small root helper" : "One-time sudo: installs Wireshark + a root helper")
            onActivated: root.run("setup")
          }

          // ── Live capture ─────────────────────────────────────────────
          Column {
            visible: cap.capturing
            width: parent.width
            spacing: Style.space(8)

            Row {
              spacing: Style.space(8)
              visible: cap.ownCapture

              Text {
                id: packetCount
                textFormat: Text.PlainText
                text: Model.groupDigits(cap.packets)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
              Text {
                anchors.baseline: packetCount.baseline
                textFormat: Text.PlainText
                text: cap.packets === 1 ? "packet" : "packets"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              InfoPair { label: "Elapsed"; value: Model.elapsedText(root.elapsed) }
              InfoPair {
                label: "Rate"
                visible: cap.ownCapture && root.elapsed >= 2
                value: Model.groupDigits(cap.packets / Math.max(1, root.elapsed)) + " pkt/s"
              }
              InfoPair { label: "Size"; value: Model.bytesText(cap.fileSize) }
              InfoPair { label: "Tuned to"; value: cap.tuning }
              InfoPair { label: "File"; value: cap.file.split("/").pop() }
            }

            Text {
              visible: cap.detachedCapture
              width: parent.width
              textFormat: Text.PlainText
              text: "This capture was started before the shell restarted, so there's no live packet count. Stopping still saves it."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ── Channel picker ───────────────────────────────────────────
          Column {
            visible: !cap.capturing && cap.channels.length > 0
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "CHANNEL"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                visible: cap.ifaceType === "managed"
                iconText: "\uf021"
                tooltipText: cap.rescanning ? "Scanning…" : "Rescan for BSSIDs (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !cap.rescanning
                opacity: enabled ? 1 : 0.4
                onClicked: cap.rescan()
              }

              Button {
                visible: cap.scan !== null
                text: "Hide empty"
                iconText: cap.hideEmpty ? "\u{f0132}" : "\u{f0131}"   // checkbox marked / blank
                tooltipText: "Only list channels where the last scan saw BSSIDs (h)"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: cap.setHideEmpty(!cap.hideEmpty)
              }

              Button {
                visible: cap.current !== null && cap.ifaceType === "managed"
                text: "Use current"
                tooltipText: "Capture on the channel you're associated on (c)"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.run("current")
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              ButtonGroup {
                options: cap.bands.map(function(b) {
                  return cap.scan ? { value: b.value, label: b.label + " · " + Model.bandCount(cap.scanSummary, b.value), tooltip: Model.bssidsText(Model.bandCount(cap.scanSummary, b.value)) + " in this band" } : b
                })
                value: cap.band
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onChanged: function(v) { cap.selectBand(v) }
              }

            }

            ChannelDropdown {
              width: parent.width
              rows: Model.channelRows(cap.bandChannelList, cap.scanSummary, cap.scan !== null && cap.hideEmpty, cap.freq)
              hasScan: cap.scan !== null
              value: String(cap.freq)
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { cap.selectChannel(parseInt(v, 10)) }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: "Width (MHz)"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ButtonGroup {
                options: cap.widthOptions
                value: cap.widthValue
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onChanged: function(v) { cap.selectWidth(v) }
              }
            }

            Text {
              visible: cap.scan !== null
              width: parent.width
              textFormat: Text.PlainText
              text: Model.scanDetail(cap.scanSummary, cap.freq)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Model.tuningText(cap.channel, cap.widthOption)
                + (cap.channel && cap.channel.radar ? " · DFS: listen only" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // ── Start / stop ─────────────────────────────────────────────
          Column {
            visible: cap.capturing || (cap.ready && !cap.stranded)
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: parent.width
              text: cap.capturing ? (cap.stopping ? "Stopping…" : "Stop capture") : "Start capture"
              iconText: cap.capturing ? "\u{f04db}" : "\u{f044a}"   // stop / record
              fontSize: Style.font.body
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: true
              enabled: cap.capturing ? !cap.stopping : cap.canStart
              opacity: enabled ? 1 : 0.4
              onClicked: root.run("toggle")
            }

            Text {
              visible: !cap.capturing
              width: parent.width
              textFormat: Text.PlainText
              text: "Wi-Fi on " + cap.iface + " disconnects while capturing and reconnects when you stop."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Toggle {
            visible: cap.ready || cap.capturing
            width: parent.width
            label: "Open in Wireshark when done"
            description: cap.wiresharkInstalled ? "" : "Wireshark isn't installed"
            checked: cap.openWhenDone
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            titleSize: Style.font.bodySmall
            onClicked: cap.setOpenWhenDone(!cap.openWhenDone)
          }

          // ── Recent captures ──────────────────────────────────────────
          PanelSeparator { visible: cap.captures.length > 0; foreground: root.foreground }

          Column {
            visible: cap.captures.length > 0
            width: parent.width
            spacing: Style.space(4)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "RECENT CAPTURES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                iconText: ""
                tooltipText: "Open " + cap.captureDir + " (f)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.run("folder")
              }
            }

            Repeater {
              model: cap.captures
              CaptureRow {
                required property var modelData
                required property int index
                width: parent.width
                capture: modelData
                isLatest: index === 0
              }
            }
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    signal activated()

    foreground: root.foreground
    hasCursor: rowMouse.containsMouse
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionRow.activated()
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component CaptureRow: CursorSurface {
    id: captureRow
    property var capture: null
    property bool isLatest: false

    foreground: root.foreground
    hasCursor: captureMouse.containsMouse
    implicitHeight: captureContent.implicitHeight + Style.space(8)

    MouseArea {
      id: captureMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { cap.openCapture(captureRow.capture.path); root.close() }
    }

    RowLayout {
      id: captureContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(2)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: captureRow.capture ? captureRow.capture.name.replace(/^aircap_/, "").replace(/\.pcapng?$/, "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: captureRow.capture
            ? Model.whenText(captureRow.capture.mtime) + " · " + Model.bytesText(captureRow.capture.size) + (captureRow.isLatest ? " · w to open" : "")
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "\u{f0256}"   // folder-search-outline
        tooltipText: "Show in folder"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: { cap.revealCapture(captureRow.capture.path); root.close() }
      }
    }
  }

  component InfoPair: RowLayout {
    property string label: ""
    property string value: ""
    property color valueColor: root.foreground

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { Layout.fillWidth: true }
    Text {
      Layout.maximumWidth: Style.space(260)
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }
  }
}

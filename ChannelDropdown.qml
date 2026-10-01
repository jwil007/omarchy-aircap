import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The kit's Dropdown, with channel rows: channel, frequency and DFS/PSC tags
// on the left; BSSIDs seen on the channel (bar + count, "+N" for wider BSSes
// bonded across it) and the strongest signal on the right.
Item {
  id: root

  property string value: ""
  property var rows: []          // Model.channelRows()
  property int maxCount: 0
  property bool hasScan: false

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int visibleRows: 10

  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }

  signal changed(string value)

  function indexOfValue(v) {
    for (var i = 0; i < rows.length; i++) if (rows[i].value === v) return i
    return -1
  }
  readonly property var currentRow: {
    var i = indexOfValue(value)
    return i >= 0 ? rows[i] : null
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: rowHeight

  BorderSurface {
    id: trigger
    width: parent.width
    height: root.rowHeight
    radius: Style.cornerRadius

    readonly property bool _focused: trigger.activeFocus
    readonly property bool _hot: triggerHover.hovered
    color: Style.controlFill(_focused, _hot, root.foreground, root.accent)
    borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)
    activeFocusOnTab: true

    HoverHandler { id: triggerHover }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        popup.opened ? popup.close() : popup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && popup.opened) {
        popup.close(); event.accepted = true
      }
    }

    ChannelRow {
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.md
      row: root.currentRow
      textColor: root.foreground
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
      text: "󰅀"
      color: Qt.darker(root.foreground, 1.2)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        popup.opened ? popup.close() : popup.open()
      }
    }

    Popup {
      id: popup
      x: 0
      y: trigger.height + Style.spacing.xxs
      width: trigger.width
      implicitHeight: Math.min(root.rows.length, root.visibleRows) * (root.popupRowHeight + Style.spacing.labelGap) + Style.spacing.xxs
      padding: Style.spacing.hairline
      leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
      rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
      topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
      bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
      focus: true

      background: BorderSurface {
        color: root.background
        borderSpec: root.popupBorderSpec
        radius: Style.cornerRadius
      }

      onOpened: {
        optionList.currentIndex = Math.max(0, root.indexOfValue(root.value))
        optionList.positionViewAtIndex(optionList.currentIndex, ListView.Center)
        optionList.forceActiveFocus()
      }

      contentItem: ListView {
        id: optionList
        spacing: Style.spacing.labelGap
        implicitHeight: contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        currentIndex: -1
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down || event.text === "j") {
            optionList.currentIndex = Math.min(root.rows.length - 1, optionList.currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            optionList.selectCurrent(); event.accepted = true
          }
        }

        function selectCurrent() {
          if (currentIndex < 0 || currentIndex >= root.rows.length) return
          var v = root.rows[currentIndex].value
          root.value = v
          root.changed(v)
          popup.close()
        }

        delegate: Rectangle {
          id: delegateRoot
          required property var modelData
          required property int index
          readonly property bool highlighted: index === optionList.currentIndex
          width: optionList.width
          height: root.popupRowHeight
          color: highlighted ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

          ChannelRow {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            row: delegateRoot.modelData
            textColor: delegateRoot.highlighted ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
            selected: delegateRoot.modelData.value === root.value
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: optionList.currentIndex = delegateRoot.index
            onClicked: optionList.selectCurrent()
          }
        }
      }
    }
  }

  component ChannelRow: RowLayout {
    id: channelRow
    property var row: null
    property color textColor: root.foreground
    property bool selected: false
    readonly property color dimColor: Qt.darker(textColor, 1.6)
    readonly property bool empty: !row || (row.count === 0 && row.overlap === 0)

    spacing: Style.space(8)

    Text {
      Layout.preferredWidth: Style.space(30)
      textFormat: Text.PlainText
      text: channelRow.row ? String(channelRow.row.ch) : ""
      color: channelRow.textColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: channelRow.selected
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: channelRow.row ? channelRow.row.freq + (channelRow.row.tags ? "  " + channelRow.row.tags : "") : ""
      color: channelRow.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    // Bar: BSSIDs whose primary channel this is, relative to the busiest.
    Rectangle {
      visible: root.hasScan
      Layout.preferredWidth: Style.space(44)
      Layout.preferredHeight: Style.space(5)
      radius: height / 2
      color: Qt.rgba(channelRow.textColor.r, channelRow.textColor.g, channelRow.textColor.b, 0.12)

      Rectangle {
        width: channelRow.row && root.maxCount > 0 ? Math.max(channelRow.row.count > 0 ? height : 0, parent.width * channelRow.row.count / root.maxCount) : 0
        height: parent.height
        radius: parent.radius
        color: root.accent
      }
    }

    Text {
      visible: root.hasScan
      Layout.preferredWidth: Style.space(44)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: !channelRow.row ? "" : channelRow.empty ? "–"
        : channelRow.row.count + (channelRow.row.overlap > 0 ? "+" + channelRow.row.overlap : "")
      color: channelRow.row && channelRow.row.count > 0 ? channelRow.textColor : channelRow.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      visible: root.hasScan
      Layout.preferredWidth: Style.space(36)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: channelRow.row && channelRow.row.best >= 0 ? Model.dbmText(channelRow.row.best) : ""
      color: channelRow.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}

import QtQuick
import qs.Commons

// One inbox line: unread dot, sender, subject, and age (+ paperclip).
Rectangle {
  id: root

  property string sender: ""
  property string subject: ""
  property string age: ""
  property bool unread: false
  property bool hasAttachments: false
  property bool selected: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal clicked()
  signal hovered()

  readonly property color textColor: selected ? Style.hoverStateColor(foreground, Color.accent) : foreground

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(44)
  radius: Style.cornerRadius
  color: selected ? Style.hoverFillFor(foreground, Color.accent) : "transparent"

  Rectangle {
    id: dot
    width: Style.space(6)
    height: width
    radius: width / 2
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    color: root.unread ? Color.accent : root.foreground
    opacity: root.unread ? 1 : 0.2
  }

  Column {
    anchors.left: dot.right
    anchors.leftMargin: Style.space(10)
    anchors.right: meta.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.sender
      elide: Text.ElideRight
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.unread
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.subject !== "" ? root.subject : "(no subject)"
      elide: Text.ElideRight
      color: Qt.darker(root.textColor, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    id: meta
    textFormat: Text.PlainText
    text: (root.hasAttachments ? "󰏢 " : "") + root.age   // nf-md-paperclip
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: root.hovered()
    onClicked: root.clicked()
  }
}

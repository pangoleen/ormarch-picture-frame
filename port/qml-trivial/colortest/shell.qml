// Does the config's own "Color" singleton win over the QtQuick one? (Qt 6.12 added QtQuick.Color.)
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  Component.onCompleted: {
    console.log("Color =", Color, "| Color.background =", Color.background, "| Color.bar =", Color.bar)
    console.log("verdict:", Color.bar === undefined ? "SHADOWED by QtQuick.Color" : "config singleton wins")
    Qt.quit()
  }
}

// Trivial Quickshell layer-shell config for the armv7h smoke test (needs a wlroots-style compositor).
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  PanelWindow {
    id: bar
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: "#1e1e2e"
    WlrLayershell.namespace: "smoke-bar"
    Text {
      id: label
      anchors.centerIn: parent
      color: "white"
      text: Qt.formatDateTime(new Date(), "hh:mm:ss") + "  " + Qt.platform.pluginName
    }
    Timer {
      interval: 1000; running: true; repeat: true
      onTriggered: {
        label.text = Qt.formatDateTime(new Date(), "hh:mm:ss") + "  " + Qt.platform.pluginName
        console.log("bar", bar.width + "x" + bar.height, "screen", bar.screen ? bar.screen.name : "none",
                    "api", label.GraphicsInfo.api, "gl", label.GraphicsInfo.majorVersion + "." + label.GraphicsInfo.minorVersion,
                    "renderableType", label.GraphicsInfo.renderableType)
      }
    }
  }
}

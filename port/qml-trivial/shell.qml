// Trivial Quickshell config for the armv7h smoke test.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  FloatingWindow {
    implicitWidth: 320
    implicitHeight: 120
    color: "#202020"
    Text {
      anchors.centerIn: parent
      color: "white"
      text: "hello from " + Qt.platform.os + " / " + Qt.platform.pluginName
    }
  }
  property int ticks: 0
  Timer {
    interval: 1000; running: true; repeat: true
    onTriggered: {
      ticks += 1
      // 2^53 and a 64-bit timestamp: checks JS number handling on a 32-bit build.
      console.log("tick", ticks, "now", Date.now(), "big", 9007199254740991, "maxint", 2147483647 + 1)
    }
  }
  Process {
    running: true
    command: ["uname", "-m"]
    stdout: StdioCollector { onStreamFinished: console.log("uname -m =", text.trim()) }
  }
}

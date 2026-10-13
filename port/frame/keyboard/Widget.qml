import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "frame.keyboard"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf11c"
    slotSize: 48
    tooltipText: "Show or hide touch keyboard"
    onPressed: {
      if (!toggle.running) toggle.running = true
    }
  }

  Process {
    id: toggle
    command: ["pf-keyboard-toggle"]
  }
}

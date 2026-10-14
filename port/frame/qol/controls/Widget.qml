import QtQuick
import Quickshell.Io
import qs.Ui

// PF1007L: Omarchy closes a window with SUPER+W or a middle click. Touch has neither.
BarWidget {
  id: root
  moduleName: "frame.controls"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: 48
    tooltipText: "Close the focused window"
    onPressed: {
      if (!closer.running) closer.running = true
    }
  }

  Process {
    id: closer
    command: ["hyprctl", "dispatch", "hl.dsp.window.close()"]
  }
}

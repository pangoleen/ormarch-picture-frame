import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// PF1007L: state of pf-dictate (local speech model). The service writes one JSON line to
// $XDG_RUNTIME_DIR/pf-dictate.state: {"state": idle|loading|listening|finishing, "busy": bool, "text": "..."}.
BarWidget {
  id: root
  moduleName: "frame.dictation"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var status: ({ state: "idle", busy: false, text: "" })
  readonly property bool listening: status.state === "listening"
  readonly property bool working: status.busy || status.state === "finishing" || status.state === "loading"

  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/pf-dictate.state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.status = JSON.parse(text()) } catch (e) {}
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.status.state === "loading" ? "" : ""
    active: root.listening || root.working
    labelText: root.status.state === "loading" ? "loading"
             : root.working ? (root.listening ? "REC …" : "…")
             : root.listening ? "REC" : ""
    tooltipText: root.status.state === "loading" ? "Loading the speech model"
               : root.listening ? "Listening" + (root.working ? ", transcribing" : "")
               : root.working ? "Transcribing" : "Dictation ready" + (root.status.text ? ": " + root.status.text : "")
  }
}

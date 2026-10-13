pragma Singleton
import QtQuick
QtObject {
  property color background: "#101315"
  readonly property QtObject bar: QtObject { property color text: "#cacccc" }
}

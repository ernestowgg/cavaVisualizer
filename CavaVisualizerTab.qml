import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    // ---------------------------------------------------------------
    // Settings
    // ---------------------------------------------------------------
    readonly property int    barCount:    pluginData.barCount    ?? 20
    readonly property int    barSpacing:  pluginData.barSpacing  ?? 4
    readonly property int    barWidth:    pluginData.barWidth    ?? 0       // 0 = auto
    readonly property int    sensitivity: pluginData.sensitivity ?? 100
    readonly property string channels:    pluginData.channels    ?? "mono"  // "mono" | "stereo"
    readonly property string orientation: pluginData.orientation ?? "bottom"
    readonly property real   bgOpacity:   (pluginData.bgOpacity  ?? 0) / 100
    readonly property real   barOpacity:  (pluginData.barOpacity ?? 100) / 100

    readonly property color barColor: {
        const choice = pluginData.colorChoice ?? "primary"
        if (choice === "secondary") return Theme.secondary
        if (choice === "surface")   return Theme.surfaceVariantText
        return Theme.primary
    }

    implicitWidth:  400
    implicitHeight: 120

    // ---------------------------------------------------------------
    // Internal state
    // ---------------------------------------------------------------
    property var barValues: []

    // True when every bar is below 1% — a small threshold because cava can
    // linger at very low values between tracks rather than snapping to zero.
    readonly property bool isSilent: {
        if (barValues.length === 0) return true
        for (let i = 0; i < barValues.length; i++) {
            if (barValues[i] > 0.01) return false
        }
        return true
    }

    // isSilent going true starts the silence timer; going false cancels it immediately.
    property bool fadedOut: true
    property bool hasPlayedOnce: false
    readonly property int silenceTimeout: (pluginData.silenceTimeout ?? 5) * 1000

    onIsSilentChanged: {
        if (isSilent) {
            if (hasPlayedOnce) silenceTimer.restart()
        } else {
            hasPlayedOnce = true
            silenceTimer.stop()
            fadedOut = false
        }
    }

    Timer {
        id: silenceTimer
        repeat: false
        interval: root.silenceTimeout
        onTriggered: root.fadedOut = true
    }

    opacity: fadedOut ? 0.0 : 1.0
    Behavior on opacity { NumberAnimation { duration: 1000; easing.type: Easing.InOutQuad } }

    // ---------------------------------------------------------------
    // Config writer
    // Rebuilds and restarts cava whenever barCount, sensitivity, or
    // channels changes — these all affect the cava config file.
    // ---------------------------------------------------------------
    // Stop cava — the rest of the chain happens in cavaProcess.onRunningChanged.
    function rebuildConfig() {
        cavaProcess.running = false
    }

    Process {
        id: configWriter
        command: [
            "bash", "-c",
            "mkdir -p /tmp/.dankshell && cat > /tmp/.dankshell/cava-widget.cfg << 'CAVAEOF'\n" +
            "[general]\n" +
            "bars = "        + root.barCount   + "\n" +
            "framerate = 60\n" +
            "sensitivity = " + root.sensitivity + "\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = 1000\n" +
            "channels = "    + root.channels   + "\n" +
            "bar_delimiter = 59\n" +
            "frame_delimiter = 10\n" +
            "CAVAEOF"
        ]
        running: false
        onRunningChanged: {
            if (!running) cavaProcess.running = true
        }
    }

    Process {
        id: cavaProcess
        command: ["cava", "-p", "/tmp/.dankshell/cava-widget.cfg"]
        running: false
        onRunningChanged: {
            // When cava stops (and it was stopped intentionally by rebuildConfig),
            // write the new config. configWriter.onRunningChanged then restarts cava.
            if (!running && !configWriter.running) {
                configWriter.running = true
            }
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!line || line.length === 0) return
                const parts = line.split(";")
                const vals = []
                for (let i = 0; i < parts.length; i++) {
                    const n = parseInt(parts[i], 10)
                    if (!isNaN(n)) vals.push(Math.min(1.0, n / 1000.0))
                }
                if (vals.length > 0) root.barValues = vals
            }
        }
    }

    Component.onCompleted:    Qt.callLater(() => { configWriter.running = true })
    onBarCountChanged:        rebuildConfig()
    onSensitivityChanged:     rebuildConfig()
    onChannelsChanged:        rebuildConfig()

    // ---------------------------------------------------------------
    // Background
    // ---------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color:   Theme.surface
        opacity: root.bgOpacity
        radius:  Theme.radius
    }

    // ---------------------------------------------------------------
    // Visualisation container
    // ---------------------------------------------------------------
    Item {
        id: vis
        anchors.fill:    parent
        anchors.margins: 8
        clip:            true

        readonly property real effectiveBarW: root.barWidth > 0
            ? root.barWidth
            : Math.max(1, (width  - (root.barCount - 1) * root.barSpacing) / root.barCount)
        readonly property real effectiveBarH: root.barWidth > 0
            ? root.barWidth
            : Math.max(1, (height - (root.barCount - 1) * root.barSpacing) / root.barCount)


        // ---- BOTTOM: bars grow upward from the bottom edge ----
        Row {
            visible: root.orientation === "bottom"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int index
                    readonly property real norm: root.barValues[index] ?? 0.0
                    width:  vis.effectiveBarW
                    height: Math.max(1, norm * vis.height)
                    y:      vis.height - height
                    Behavior on height { SmoothedAnimation { velocity: vis.height * 4 } }
                    radius:  2
                    color:   root.barColor
                    opacity: root.barOpacity * (0.85 + norm * 0.15)
                }
            }
        }

        // ---- TOP: bars grow downward from the top edge ----
        Row {
            visible: root.orientation === "top"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int index
                    readonly property real norm: root.barValues[index] ?? 0.0
                    width:  vis.effectiveBarW
                    height: Math.max(1, norm * vis.height)
                    y:      0
                    Behavior on height { SmoothedAnimation { velocity: vis.height * 4 } }
                    radius:  2
                    color:   root.barColor
                    opacity: root.barOpacity * (0.85 + norm * 0.15)
                }
            }
        }

        // ---- LEFT: bars grow rightward from the left edge ----
        Column {
            visible: root.orientation === "left"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int index
                    readonly property real norm: root.barValues[index] ?? 0.0
                    height: vis.effectiveBarH
                    width:  Math.max(1, norm * vis.width)
                    x:      0
                    Behavior on width { SmoothedAnimation { velocity: vis.width * 4 } }
                    radius:  2
                    color:   root.barColor
                    opacity: root.barOpacity * (0.85 + norm * 0.15)
                }
            }
        }

        // ---- RIGHT: bars grow leftward from the right edge ----
        Column {
            visible: root.orientation === "right"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int index
                    readonly property real norm: root.barValues[index] ?? 0.0
                    height: vis.effectiveBarH
                    width:  Math.max(1, norm * vis.width)
                    x:      vis.width - width
                    Behavior on width { SmoothedAnimation { velocity: vis.width * 4 } }
                    radius:  2
                    color:   root.barColor
                    opacity: root.barOpacity * (0.85 + norm * 0.15)
                }
            }
        }

        // ---- HORIZONTAL: bars grow up and down from the vertical center ----
        Row {
            visible: root.orientation === "horizontal"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int index
                    readonly property real norm: root.barValues[index] ?? 0.0
                    width:  vis.effectiveBarW
                    height: Math.max(1, norm * vis.height)
                    y:      vis.height / 2 - height / 2
                    Behavior on height { SmoothedAnimation { velocity: vis.height * 4 } }
                    radius:  2
                    color:   root.barColor
                    opacity: root.barOpacity * (0.85 + norm * 0.15)
                }
            }
        }

    } // vis
}

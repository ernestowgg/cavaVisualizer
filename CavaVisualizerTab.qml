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
    property var  barValues: []

    // Set directly inside the parse loop rather than computed as a
    // binding — avoids a full array scan 60 times per second.
    property bool isSilent: true

    property bool fadedOut:     true
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
    Timer {
        id: rebuildTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (cavaProcess.running) {
                // Running normally — stop it; cavaProcess.onRunningChanged will
                // start configWriter, which will restart cava with the new config.
                cavaProcess.running = false
            } else if (!configWriter.running) {
                // Initial startup, or cava wasn't running for some reason —
                // kick off configWriter directly.
                configWriter.running = true
            }
            // If configWriter is already running, a rebuild is already in
            // progress and cavaProcess will be started when it finishes.
        }
    }

    function rebuildConfig() {
        rebuildTimer.restart()
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
            "channels = "    + root.channels   + "\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "channels = "    + root.channels   + "\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = 1000\n" +
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
                let silent = true
                for (let i = 0; i < parts.length; i++) {
                    const n = parseInt(parts[i], 10)
                    if (!isNaN(n)) {
                        const v = Math.min(1.0, n / 1000.0)
                        vals.push(v)
                        if (v > 0.01) silent = false
                    }
                }
                if (vals.length > 0) {
                    root.barValues = vals
                    root.isSilent = silent
                }
            }
        }
    }

    Component.onCompleted:    rebuildConfig()
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

        // barWidth doubles as the fixed dimension for vertical orientations (left/right),
        // producing square bars when set. When 0, distribute height evenly.
        readonly property real effectiveBarH: root.barWidth > 0
            ? root.barWidth
            : Math.max(1, (height - (root.barCount - 1) * root.barSpacing) / root.barCount)

        // ---- BOTTOM / TOP / HORIZONTAL ----
        // A single Repeater handles all three horizontal-axis orientations.
        // The only difference is the y anchor of each bar.
        Row {
            visible: root.orientation === "bottom"
                  || root.orientation === "top"
                  || root.orientation === "horizontal"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int  index
                    readonly property real norm: root.barValues[index] ?? 0.0

                    width:  vis.effectiveBarW
                    height: Math.max(1, norm * vis.height)
                    y:      root.orientation === "bottom"     ? vis.height - height
                          : root.orientation === "horizontal" ? vis.height / 2 - height / 2
                          :                                     0

                    Behavior on height { SmoothedAnimation { velocity: vis.height * 4 } }

                    radius: 2
                    // Encode brightness modulation in the alpha channel rather than
                    // the item's opacity property. Items with a uniform opacity
                    // property can be batched into a single draw call by the scene
                    // graph; non-uniform per-item opacity values each force their own.
                    color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
                                   root.barOpacity * (0.85 + norm * 0.15))
                }
            }
        }

        // ---- LEFT / RIGHT ----
        // Bars grow horizontally; only the x anchor differs between the two.
        Column {
            visible: root.orientation === "left"
                  || root.orientation === "right"
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    required property int  index
                    readonly property real norm: root.barValues[index] ?? 0.0

                    height: vis.effectiveBarH
                    width:  Math.max(1, norm * vis.width)
                    x:      root.orientation === "right" ? vis.width - width : 0

                    Behavior on width { SmoothedAnimation { velocity: vis.width * 4 } }

                    radius: 2
                    color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
                                   root.barOpacity * (0.85 + norm * 0.15))
                }
            }
        }

    } // vis
}

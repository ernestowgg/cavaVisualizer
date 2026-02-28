import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "cavaVisualizer"

    // --- Layout ---

    SliderSetting {
        settingKey:   "barCount"
        label:        I18n.tr("Bar Count")
        defaultValue: 20
        minimum:      4
        maximum:      64
    }

    SliderSetting {
        settingKey:   "barSpacing"
        label:        I18n.tr("Bar Spacing")
        defaultValue: 4
        minimum:      0
        maximum:      16
        unit:         "px"
    }

    SliderSetting {
        settingKey:   "barWidth"
        label:        I18n.tr("Bar Width")
        description:  I18n.tr("Fixed bar width in pixels. Set to 0 to fill the widget evenly.")
        defaultValue: 0
        minimum:      0
        maximum:      32
        unit:         "px"
    }

    // --- Orientation ---

    SelectionSetting {
        settingKey:   "orientation"
        label:        I18n.tr("Orientation")
        defaultValue: "bottom"
        options: [
            { label: I18n.tr("Bottom"), value: "bottom" },
            { label: I18n.tr("Top"),    value: "top" },
            { label: I18n.tr("Left"),   value: "left" },
            { label: I18n.tr("Right"),  value: "right" }
        ]
    }

    // --- Audio ---

    SliderSetting {
        settingKey:   "sensitivity"
        label:        I18n.tr("Sensitivity")
        defaultValue: 100
        minimum:      10
        maximum:      300
        unit:         "%"
    }

    SelectionSetting {
        settingKey:   "channels"
        label:        I18n.tr("Channels")
        description:  I18n.tr("Stereo mirrors both channels with low frequencies in the center. Mono outputs left to right, lowest to highest frequency.")
        defaultValue: "mono"
        options: [
            { label: I18n.tr("Mono"),   value: "mono" },
            { label: I18n.tr("Stereo"), value: "stereo" }
        ]
    }

    // --- Appearance ---

    SelectionSetting {
        settingKey:   "colorChoice"
        label:        I18n.tr("Bar Colour")
        defaultValue: "primary"
        options: [
            { label: I18n.tr("Primary"),   value: "primary" },
            { label: I18n.tr("Secondary"), value: "secondary" },
            { label: I18n.tr("Surface"),   value: "surface" }
        ]
    }

    SliderSetting {
        settingKey:   "silenceTimeout"
        label:        I18n.tr("Fade Out Delay")
        description:  I18n.tr("Seconds of silence before the widget fades out")
        defaultValue: 5
        minimum:      1
        maximum:      30
        unit:         "s"
    }

    SliderSetting {
        settingKey:   "bgOpacity"
        label:        I18n.tr("Background Opacity")
        defaultValue: 0
        minimum:      0
        maximum:      100
        unit:         "%"
    }

    SliderSetting {
        settingKey:   "barOpacity"
        label:        I18n.tr("Bar Opacity")
        defaultValue: 100
        minimum:      0
        maximum:      100
        unit:         "%"
    }
}

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    activationTogglesExpanded: true
    Plasmoid.title: "cachyAgent"

    // fc-list | grep -i nerd -> Nerd Font mevcut ("MesloLGS Nerd Font").
    // Varsa panelde NF glifi, yoksa hicolor'daki cachy-agent SVG ikonu.
    property bool hasNerdFont: true
    property var providersData: []
    property var catalogData: []
    property bool alarm: false
    property bool loading: false
    property string lastError: ""

    // Tema uyumlu palet (açık/koyu temada okunabilir; koyu temada Tokyo Night'a yakın)
    property color tnText: Kirigami.Theme.textColor
    property color tnMuted: Kirigami.Theme.disabledTextColor
    property color tnAccent: Kirigami.Theme.highlightColor
    property color tnCard: Qt.lighter(Kirigami.Theme.backgroundColor, 1.3)
    property color tnCardBorder: Qt.alpha(Kirigami.Theme.textColor, 0.25)
    property color tnTrack: Qt.darker(Kirigami.Theme.backgroundColor, 1.2)

    property string updateCommand: "__HOME__/.local/bin/cachy-agent-usage-update"
    property string installBase: "/usr/bin/alacritty --class CachyAgent -e __HOME__/.local/bin/cachy-agent-install "
    // Katalog agents.conf'tan gelir: {"catalog":[{"id","name","installed","external"}]}
    property string catalogCommand: "__HOME__/.local/bin/cachy-agent-agents json"
    property string fetchCommand: "python3 -c 'import json, glob, os; F=sorted(glob.glob(os.path.expanduser(\"~/.local/state/cachy-agent/agents/usage/*.json\"))); P=[{\"id\": str(d.get(\"id\", os.path.basename(p)[:-5])), \"name\": str(d.get(\"name\", d.get(\"id\", os.path.basename(p)[:-5]))), \"today\": int(d.get(\"todayPrompts\") or 0), \"total\": int(d.get(\"totalPrompts\") or 0), \"limits\": [{\"label\": str(x.get(\"label\", \"\")), \"percent\": float(x.get(\"percent\", 0) or 0), \"resetsAt\": str(x.get(\"resetsAt\", \"\"))} for x in (d.get(\"limits\") or [])]} for p, d in [(p, json.load(open(p))) for p in F]]; print(json.dumps({\"providers\": P, \"alarm\": any(l[\"percent\"] >= 0.9 for pr in P for l in pr[\"limits\"])}))'"

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var stdout = String(data["stdout"] || "").trim();
            if (sourceName === root.updateCommand) {
                executable.exec(root.fetchCommand);
            } else if (sourceName === root.fetchCommand) {
                root.loading = false;
                if (stdout === "") {
                    root.lastError = "boş çıktı";
                } else {
                    try {
                        var obj = JSON.parse(stdout);
                        root.providersData = obj.providers || [];
                        root.alarm = !!obj.alarm;
                        root.lastError = "";
                    } catch (e) {
                        root.lastError = "parse hatası";
                    }
                }
            } else if (sourceName === root.catalogCommand) {
                if (stdout !== "") {
                    try {
                        var cat = JSON.parse(stdout);
                        root.catalogData = cat.catalog || [];
                    } catch (e) {
                        // katalog parse hatası yoksay, bir sonraki turda tekrar denenecek
                    }
                }
            } else if (sourceName.indexOf(root.installBase) === 0) {
                // fire-and-forget kurulum terminali: çıktısı yoksay
            } else {
                root.loading = false;
            }
            disconnectSource(sourceName);
        }
        function exec(cmd) {
            if (cmd) {
                connectSource(cmd);
            }
        }
    }

    function refresh() {
        root.loading = true;
        executable.exec(fetchCommand);
        executable.exec(catalogCommand);
    }

    function refreshAll() {
        root.loading = true;
        executable.exec(updateCommand);
    }

    Timer {
        id: pollTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    compactRepresentation: Item {
        id: compact
        Text {
            visible: root.hasNerdFont
            anchors.centerIn: parent
            text: "󱚣"
            font.family: "MesloLGS Nerd Font"
            font.pixelSize: Math.max(10, Math.min(compact.width, compact.height) - 4)
            color: root.alarm ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
        Kirigami.Icon {
            visible: !root.hasNerdFont
            anchors.fill: parent
            source: "cachy-agent"
        }
        Rectangle {
            visible: root.alarm
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 2
            anchors.rightMargin: 2
            width: 8
            height: 8
            radius: 4
            color: Kirigami.Theme.negativeTextColor
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: 400
        Layout.preferredHeight: 720
        Layout.minimumWidth: 320
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents3.Label {
                    text: "cachyAgent"
                    font.pointSize: 15
                    font.bold: true
                    color: root.tnText
                }
                PlasmaComponents3.Label {
                    text: "provider kullanımı"
                    font.pointSize: 11
                    color: root.tnMuted
                }
            }
            PlasmaComponents3.Button {
                text: "Yenile"
                enabled: !root.loading
                onClicked: root.refreshAll()
            }
        }

        PlasmaComponents3.Label {
            visible: root.alarm && root.lastError === ""
            text: "⚠ bir limit %90'ı aştı"
            font.pointSize: 11
            font.bold: true
            color: Kirigami.Theme.negativeTextColor
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            visible: root.lastError !== ""
            text: root.lastError
            font.pointSize: 11
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        ColumnLayout {
            visible: root.lastError === "" && root.providersData.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                text: "◌"
                font.pointSize: 28
                color: root.tnMuted
                opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }
            PlasmaComponents3.Label {
                text: "henüz kayıt yok"
                font.pointSize: 13
                font.bold: true
                color: root.tnMuted
                Layout.alignment: Qt.AlignHCenter
            }
            PlasmaComponents3.Label {
                text: root.loading ? "Yükleniyor…" : "Veriler birazdan burada görünecek."
                font.pointSize: 11
                color: root.tnMuted
                opacity: 0.8
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }

        Repeater {
            model: root.providersData
            delegate: Rectangle {
                required property var modelData
                property var provider: modelData
                Layout.fillWidth: true
                Layout.preferredHeight: cardCol.implicitHeight + 28
                radius: 12
                color: root.tnCard
                border.color: root.tnCardBorder
                border.width: 1
                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: provider.name
                        font.pointSize: 13
                        font.bold: true
                        color: root.tnText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents3.Label {
                        text: "bugün " + provider.today + "  ·  toplam " + provider.total
                        font.pointSize: 11
                        color: root.tnMuted
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: provider.limits
                        delegate: ColumnLayout {
                            required property var modelData
                            property var lim: modelData
                            spacing: 4
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents3.Label {
                                    text: lim.label
                                    font.pointSize: 11
                                    color: root.tnText
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(lim.percent * 100) + "%"
                                    font.pointSize: 11
                                    font.bold: true
                                    color: lim.percent >= 0.9 ? Kirigami.Theme.negativeTextColor : root.tnAccent
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8
                                radius: 4
                                color: root.tnTrack
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(8, parent.width * Math.min(1, lim.percent))
                                    radius: 4
                                    color: lim.percent >= 0.9 ? Kirigami.Theme.negativeTextColor : root.tnAccent
                                }
                            }
                            PlasmaComponents3.Label {
                                visible: lim.resetsAt !== ""
                                text: "reset: " + lim.resetsAt
                                font.pointSize: 11
                                color: root.tnMuted
                                opacity: 0.8
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        PlasmaComponents3.Label {
            text: "Katalog"
            font.pointSize: 13
            font.bold: true
            color: root.tnText
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        Repeater {
            model: root.catalogData
            delegate: RowLayout {
                required property var modelData
                property var entry: modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 5
                    color: entry.installed ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    Layout.alignment: Qt.AlignVCenter
                }
                PlasmaComponents3.Label {
                    text: entry.id
                    font.pointSize: 11
                    color: root.tnText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    visible: entry.installed
                    text: "izleniyor"
                    font.pointSize: 11
                    color: Kirigami.Theme.positiveTextColor
                }
                PlasmaComponents3.Button {
                    visible: !entry.installed
                    text: "Kur"
                    onClicked: executable.exec(root.installBase + entry.id)
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}

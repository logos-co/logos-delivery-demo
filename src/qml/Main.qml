import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root

    readonly property var backend: logos.module("logos_delivery_demo")

    // QML-side state — single source of truth for the UI.
    // The backend forwards delivery_module events into this model.
    property var topics: ({})       // { topic: [ {direction, text, hash, requestId, ts, state} ] }
    property var topicList: []      // ordered list of subscribed topics
    property string selectedTopic: ""

    readonly property string nodeStatus: backend ? backend.connectionStatus : "no backend"
    readonly property bool   nodeReady:  backend ? backend.nodeReady       : false
    readonly property string peerIdValue: backend ? backend.peerId          : ""
    readonly property int    peerCountValue: backend ? backend.peerCount    : 0
    readonly property int    portsShiftValue: backend ? backend.portsShift  : 0
    readonly property string lastErrorValue: backend ? backend.lastError    : ""

    Connections {
        target: backend
        ignoreUnknownSignals: true

        function onMessageReceived(topic, payloadBase64, messageHash, timestamp) {
            root.appendMessage(topic, {
                direction: "in",
                text: Qt.atob(payloadBase64),
                hash: messageHash,
                ts: timestamp,
                state: "received"
            })
        }

        function onMessageSentNotif(requestId, messageHash) {
            root.updateOutgoing(requestId, { hash: messageHash, state: "sent" })
        }

        function onMessagePropagatedNotif(requestId, messageHash) {
            root.updateOutgoing(requestId, { hash: messageHash, state: "propagated" })
        }

        function onMessageErrorNotif(requestId, errorText) {
            root.updateOutgoing(requestId, { state: "error", errorText: errorText })
        }
    }

    function appendMessage(topic, msg) {
        const cur = root.topics[topic] || []
        cur.push(msg)
        const copy = Object.assign({}, root.topics)
        copy[topic] = cur
        root.topics = copy
        if (topic === root.selectedTopic) messageView.model = cur
    }

    function updateOutgoing(requestId, patch) {
        const next = Object.assign({}, root.topics)
        for (const t in next) {
            for (const m of next[t]) {
                if (m.requestId === requestId) Object.assign(m, patch)
            }
        }
        root.topics = next
        if (root.selectedTopic) messageView.model = next[root.selectedTopic] || []
    }

    function addTopic(topic) {
        const trimmed = (topic || "").trim()
        if (!trimmed) return
        if (root.topicList.indexOf(trimmed) >= 0) {
            root.selectedTopic = trimmed
            messageView.model = root.topics[trimmed] || []
            return
        }
        logos.watch(backend.subscribe(trimmed),
            function(err) {
                if (err && err.length > 0) return
                root.topicList = root.topicList.concat([trimmed])
                const copy = Object.assign({}, root.topics)
                copy[trimmed] = []
                root.topics = copy
                root.selectedTopic = trimmed
                messageView.model = copy[trimmed]
                topicInput.text = ""
            },
            function(_e) {}
        )
    }

    function removeTopic(topic) {
        if (!topic) return
        logos.watch(backend.unsubscribe(topic),
            function(err) {
                if (err && err.length > 0) return
                root.topicList = root.topicList.filter(function(t) { return t !== topic })
                const copy = Object.assign({}, root.topics)
                delete copy[topic]
                root.topics = copy
                if (root.selectedTopic === topic) {
                    root.selectedTopic = root.topicList.length > 0 ? root.topicList[0] : ""
                    messageView.model = root.selectedTopic ? (copy[root.selectedTopic] || []) : []
                }
            },
            function(_e) {}
        )
    }

    function sendOutgoing(topic, text) {
        if (!topic || !text) return
        logos.watch(backend.sendMessage(topic, text),
            function(requestId) {
                if (!requestId || requestId.length === 0) return
                root.appendMessage(topic, {
                    direction: "out",
                    text: text,
                    requestId: requestId,
                    state: "pending",
                    ts: ""
                })
                sendInput.text = ""
            },
            function(_e) {}
        )
    }

    // ─── Layout ────────────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.palette.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.small
        spacing: Theme.spacing.small

        // ── Header / health bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusMedium
            border.width: 1
            border.color: Theme.palette.borderHairline

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing.medium
                anchors.rightMargin: Theme.spacing.medium
                spacing: Theme.spacing.medium

                LogosText {
                    text: "Logos Delivery demo"
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightBold
                }

                Item { Layout.fillWidth: true }

                // Connection status pill
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: statusRow.implicitWidth + Theme.spacing.medium
                    radius: Theme.spacing.radiusPill
                    color: Theme.palette.backgroundElevated
                    border.width: 1
                    border.color: root.nodeReady ? Theme.palette.success : Theme.palette.warning

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.small

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: root.nodeReady ? Theme.palette.success : Theme.palette.warning
                        }
                        LogosText {
                            text: root.nodeReady ? root.nodeStatus : "starting…"
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                    }
                }

                // Peers count pill
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: peersRow.implicitWidth + Theme.spacing.medium
                    radius: Theme.spacing.radiusPill
                    color: Theme.palette.backgroundElevated
                    border.width: 1
                    border.color: Theme.palette.borderHairline

                    ToolTip.visible: peerArea.containsMouse
                    ToolTip.delay: 200
                    ToolTip.text: "Polled from delivery_module.getNodeInfo(\"Metrics\") every 3s — parsed from the libp2p_peers gauge."

                    MouseArea { id: peerArea; anchors.fill: parent; hoverEnabled: true }

                    RowLayout {
                        id: peersRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.small
                        LogosText {
                            text: "peers " + root.peerCountValue
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                    }
                }

                // Peer ID pill (truncated, click to copy is left for the user to add)
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: idRow.implicitWidth + Theme.spacing.medium
                    visible: root.peerIdValue.length > 0
                    radius: Theme.spacing.radiusPill
                    color: Theme.palette.backgroundElevated
                    border.width: 1
                    border.color: Theme.palette.borderHairline

                    ToolTip.visible: idArea.containsMouse
                    ToolTip.delay: 200
                    ToolTip.text: "My peer ID (delivery_module.getNodeInfo(\"MyPeerId\")):\n" + root.peerIdValue +
                                  "\n\nPort shift this instance: " + root.portsShiftValue +
                                  " (derived from LogosInstance::id so two instances on one host don't collide)."

                    MouseArea { id: idArea; anchors.fill: parent; hoverEnabled: true }

                    RowLayout {
                        id: idRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.small
                        LogosText {
                            text: "me " + root.peerIdValue.slice(0, 6) + "…" + root.peerIdValue.slice(-4)
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                            font.family: "monospace"
                        }
                    }
                }
            }
        }

        // ── Body
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing.small

            // ─── Left: topics
            Rectangle {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                color: Theme.palette.backgroundSecondary
                radius: Theme.spacing.radiusMedium
                border.width: 1
                border.color: Theme.palette.borderHairline

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.small
                    spacing: Theme.spacing.small

                    RowLayout {
                        LogosText {
                            text: "Content topics"
                            font.pixelSize: Theme.typography.subtitleText
                            font.weight: Theme.typography.weightBold
                            Layout.fillWidth: true
                        }
                        InfoChip {
                            tip: "Add → delivery_module.subscribe(topic)\nRemove → delivery_module.unsubscribe(topic)\nBoth return LogosResult."
                        }
                    }

                    RowLayout {
                        LogosTextField {
                            id: topicInput
                            placeholderText: "/myapp/1/chat/proto"
                            Layout.fillWidth: true
                            onAccepted: root.addTopic(text)
                        }
                        LogosButton {
                            text: "+"
                            implicitWidth: 40
                            implicitHeight: 40
                            enabled: root.nodeReady && topicInput.text.length > 0
                            onClicked: root.addTopic(topicInput.text)
                        }
                    }

                    ListView {
                        id: topicListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.topicList
                        clip: true
                        spacing: 2

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 36
                            color: modelData === root.selectedTopic
                                   ? Theme.palette.backgroundElevated
                                   : "transparent"
                            radius: Theme.spacing.radiusSmall

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing.small
                                anchors.rightMargin: Theme.spacing.tiny
                                spacing: Theme.spacing.tiny

                                LogosText {
                                    text: modelData
                                    font.pixelSize: Theme.typography.secondaryText
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedTopic = modelData
                                            messageView.model = root.topics[modelData] || []
                                        }
                                    }
                                }

                                LogosButton {
                                    text: "×"
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    onClicked: root.removeTopic(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ─── Right: conversation
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.palette.backgroundSecondary
                radius: Theme.spacing.radiusMedium
                border.width: 1
                border.color: Theme.palette.borderHairline

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.small
                    spacing: Theme.spacing.small

                    RowLayout {
                        LogosText {
                            text: root.selectedTopic.length > 0
                                  ? root.selectedTopic
                                  : "Select or add a content topic"
                            font.pixelSize: Theme.typography.subtitleText
                            font.weight: Theme.typography.weightBold
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        InfoChip {
                            tip: "Incoming messages arrive via the messageReceived event.\nPayload is base64; the demo decodes it with Qt.atob()."
                        }
                    }

                    ListView {
                        id: messageView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Theme.spacing.tiny
                        model: []

                        delegate: MessageBubble { msg: modelData }
                    }

                    RowLayout {
                        LogosTextField {
                            id: sendInput
                            placeholderText: root.selectedTopic.length > 0
                                             ? "Message to " + root.selectedTopic
                                             : "Pick a topic first"
                            Layout.fillWidth: true
                            enabled: root.nodeReady && root.selectedTopic.length > 0
                            onAccepted: root.sendOutgoing(root.selectedTopic, text)
                        }
                        LogosButton {
                            text: "Send"
                            enabled: root.nodeReady
                                     && root.selectedTopic.length > 0
                                     && sendInput.text.length > 0
                            onClicked: root.sendOutgoing(root.selectedTopic, sendInput.text)
                        }
                        InfoChip {
                            tip: "Send calls delivery_module.send(topic, text). The module base64-encodes for you. LogosResult.getString() is the request id; track it via messageSent → messagePropagated (or messageError)."
                        }
                    }

                    Rectangle {
                        visible: root.lastErrorValue.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: Theme.spacing.radiusSmall
                        color: Qt.rgba(Theme.palette.error.r, Theme.palette.error.g, Theme.palette.error.b, 0.15)
                        border.width: 1
                        border.color: Theme.palette.error
                        LogosText {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing.small
                            verticalAlignment: Text.AlignVCenter
                            text: root.lastErrorValue
                            color: Theme.palette.error
                            font.pixelSize: Theme.typography.secondaryText
                        }
                    }
                }
            }
        }
    }

    // ── Reusable inline components ────────────────────────────────────────────

    component InfoChip: Rectangle {
        property string tip: ""
        implicitWidth: 22
        implicitHeight: 22
        radius: 11
        color: Theme.palette.backgroundElevated
        border.width: 1
        border.color: Theme.palette.borderHairline

        ToolTip.visible: infoArea.containsMouse && tip.length > 0
        ToolTip.delay: 200
        ToolTip.text: tip

        LogosText {
            anchors.centerIn: parent
            text: "?"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        MouseArea {
            id: infoArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }
    }

    component MessageBubble: Rectangle {
        property var msg
        readonly property bool outgoing: msg && msg.direction === "out"
        readonly property string stateGlyph: {
            if (!msg) return ""
            switch (msg.state) {
                case "error":      return "✕"
                case "propagated": return "✓✓"
                case "sent":       return "✓"
                case "pending":    return "…"
                case "received":   return ""   // incoming: no glyph
                default:           return ""
            }
        }
        readonly property color stateColor: {
            if (msg && msg.state === "error")      return Theme.palette.error
            if (msg && msg.state === "propagated") return Theme.palette.success
            return Theme.palette.textSecondary
        }

        width: ListView.view ? ListView.view.width : implicitWidth
        height: msgRow.implicitHeight + Theme.spacing.small * 2
        radius: Theme.spacing.radiusMedium
        color: outgoing ? Theme.palette.surface : Theme.palette.backgroundElevated
        border.width: 1
        border.color: Theme.palette.borderHairline

        ToolTip.visible: bubbleArea.containsMouse && msg && (msg.hash || msg.requestId || msg.errorText)
        ToolTip.delay: 400
        ToolTip.text: {
            if (!msg) return ""
            const parts = []
            if (msg.hash)       parts.push("hash: " + msg.hash)
            if (msg.requestId)  parts.push("requestId: " + msg.requestId)
            if (msg.errorText)  parts.push("error: " + msg.errorText)
            if (msg.ts)         parts.push("ts: " + msg.ts)
            return parts.join("\n")
        }

        MouseArea { id: bubbleArea; anchors.fill: parent; hoverEnabled: true }

        RowLayout {
            id: msgRow
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.medium
            anchors.rightMargin: Theme.spacing.medium
            anchors.topMargin: Theme.spacing.small
            anchors.bottomMargin: Theme.spacing.small
            spacing: Theme.spacing.small

            LogosText {
                text: msg ? msg.text : ""
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }

            LogosText {
                visible: stateGlyph.length > 0
                text: stateGlyph
                color: stateColor
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }
}

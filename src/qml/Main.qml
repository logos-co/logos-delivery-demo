import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root

    readonly property var backend: logos.module("logos_delivery_demo")

    // Event log per topic. Each entry is one observed event:
    //   { eventName, direction, topic, payload, hash, requestId, errorText, ts }
    // The view renders events verbatim — this is a developer demo.
    property var eventsByTopic: ({})
    property var topicList: []
    property string selectedTopic: ""

    readonly property string nodeStatus:    backend ? backend.connectionStatus : "no backend"
    readonly property bool   nodeReady:     backend ? backend.nodeReady       : false
    readonly property string peerIdValue:   backend ? backend.peerId          : ""
    readonly property int    peerCountValue: backend ? backend.peerCount      : 0
    readonly property string lastErrorValue: backend ? backend.lastError      : ""

    Connections {
        target: backend
        ignoreUnknownSignals: true

        function onMessageReceived(topic, payload, messageHash, timestamp) {
            root.logEvent(topic, {
                eventName: "messageReceived",
                direction: "in",
                topic: topic,
                payload: payload,
                hash: messageHash,
                ts: timestamp
            })
        }

        function onMessageSentNotif(requestId, messageHash, timestamp) {
            root.logEvent(null, {
                eventName: "messageSent",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                ts: timestamp
            })
        }

        function onMessagePropagatedNotif(requestId, messageHash, timestamp) {
            root.logEvent(null, {
                eventName: "messagePropagated",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                ts: timestamp
            })
        }

        function onMessageErrorNotif(requestId, messageHash, errorText, timestamp) {
            root.logEvent(null, {
                eventName: "messageError",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                errorText: errorText,
                ts: timestamp
            })
        }
    }

    // Append an event into the per-topic log. When `topic` is null (lifecycle
    // events without a topic field), the entry is placed on the currently
    // selected topic so the user can see correlation with the message they sent.
    function logEvent(topic, evt) {
        const targetTopic = topic && topic.length > 0 ? topic : root.selectedTopic
        if (!targetTopic) return
        const cur = root.eventsByTopic[targetTopic] || []
        cur.push(evt)
        const next = Object.assign({}, root.eventsByTopic)
        next[targetTopic] = cur
        root.eventsByTopic = next
        if (targetTopic === root.selectedTopic) eventView.model = cur
    }

    function addTopic(topic) {
        const trimmed = (topic || "").trim()
        if (!trimmed) return
        if (root.topicList.indexOf(trimmed) >= 0) {
            root.selectedTopic = trimmed
            eventView.model = root.eventsByTopic[trimmed] || []
            return
        }
        logos.watch(backend.subscribe(trimmed),
            function(err) {
                if (err && err.length > 0) return
                root.topicList = root.topicList.concat([trimmed])
                const next = Object.assign({}, root.eventsByTopic)
                next[trimmed] = []
                root.eventsByTopic = next
                root.selectedTopic = trimmed
                eventView.model = next[trimmed]
                root.logEvent(trimmed, {
                    eventName: "subscribe() returned",
                    direction: "local",
                    topic: trimmed
                })
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
                const next = Object.assign({}, root.eventsByTopic)
                delete next[topic]
                root.eventsByTopic = next
                if (root.selectedTopic === topic) {
                    root.selectedTopic = root.topicList.length > 0 ? root.topicList[0] : ""
                    eventView.model = root.selectedTopic ? (next[root.selectedTopic] || []) : []
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
                root.logEvent(topic, {
                    eventName: "send() returned",
                    direction: "local",
                    topic: topic,
                    payload: text,
                    requestId: requestId
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

        // ─── Header / health area ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: headerCol.implicitHeight + Theme.spacing.medium * 2
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusMedium
            border.width: 1
            border.color: Theme.palette.borderHairline

            ColumnLayout {
                id: headerCol
                anchors.fill: parent
                anchors.margins: Theme.spacing.medium
                spacing: Theme.spacing.small

                // Row 1: title + badges with adjacent info chips
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    LogosText {
                        text: "Logos Delivery demo"
                        font.pixelSize: Theme.typography.panelTitleText
                        font.weight: Theme.typography.weightBold
                    }

                    Item { Layout.fillWidth: true }

                    LogosBadge {
                        text: root.nodeReady ? root.nodeStatus : "starting…"
                        color: root.nodeReady ? Theme.palette.success : Theme.palette.warning
                    }

                    LogosBadge {
                        text: "peers: " + root.peerCountValue
                        color: root.peerCountValue > 0 ? Theme.palette.success : Theme.palette.textSecondary
                    }
                    InfoChip {
                        tip: "<b>peers</b> — number of currently-connected libp2p peers.<br><br>"
                           + "Polled every 3 seconds from "
                           + "<code>delivery_module.getNodeInfo(\"Metrics\")</code> "
                           + "and parsed out of the <code>libp2p_peers</code> Prometheus gauge."
                    }
                }

                // Row 2: Peer ID (full id rendered as monospace text)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: "Peer ID:"
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    LogosText {
                        text: root.peerIdValue.length > 0
                              ? root.peerIdValue
                              : "(not available yet)"
                        font.pixelSize: Theme.typography.primaryText
                        font.family: "monospace"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    InfoChip {
                        tip: "<b>Peer ID</b> — this node's local libp2p peer identifier.<br><br>"
                           + "Returned by <code>delivery_module.getNodeInfo(\"MyPeerId\")</code>, "
                           + "polled every 3 seconds together with the peer count."
                    }
                }

                // Error line (only when non-empty)
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
                        font.pixelSize: Theme.typography.primaryText
                    }
                }
            }
        }

        // ─── Body ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing.small

            // ── Left: content topics ─────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: Theme.palette.backgroundSecondary
                radius: Theme.spacing.radiusMedium
                border.width: 1
                border.color: Theme.palette.borderHairline
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Header (margin-padded)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.spacing.medium
                        spacing: Theme.spacing.small

                        LogosText {
                            text: "Content topics"
                            font.pixelSize: Theme.typography.subtitleText
                            font.weight: Theme.typography.weightBold
                            Layout.fillWidth: true
                        }
                        InfoChip {
                            tip: "<b>Content topics</b> — the libp2p pubsub topics this node is subscribed to.<br><br>"
                               + "Adding a topic calls <code>delivery_module.subscribe(topic)</code>.<br>"
                               + "Removing one calls <code>delivery_module.unsubscribe(topic)</code>.<br>"
                               + "Both return a <code>LogosResult</code>; the demo logs the return value as a local event."
                        }
                    }

                    // Input row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacing.medium
                        Layout.rightMargin: Theme.spacing.medium
                        Layout.bottomMargin: Theme.spacing.small
                        spacing: Theme.spacing.small

                        LogosTextField {
                            id: topicInput
                            placeholderText: "/myapp/1/chat/proto"
                            Layout.fillWidth: true
                        }
                        Connections {
                            target: topicInput.textInput
                            function onAccepted() { root.addTopic(topicInput.text) }
                        }
                        LogosButton {
                            text: "+"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            implicitWidth: 40
                            implicitHeight: 40
                            enabled: root.nodeReady && topicInput.text.length > 0
                            onClicked: root.addTopic(topicInput.text)
                        }
                    }

                    // Full-width topic list. No horizontal margin — the highlight
                    // rectangle spans the panel edges.
                    ListView {
                        id: topicListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.topicList
                        clip: true
                        spacing: 0

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 40
                            color: modelData === root.selectedTopic
                                   ? Theme.palette.primary
                                   : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing.medium
                                anchors.rightMargin: Theme.spacing.tiny
                                spacing: Theme.spacing.tiny

                                LogosText {
                                    text: modelData
                                    font.pixelSize: Theme.typography.primaryText
                                    color: modelData === root.selectedTopic
                                           ? Theme.palette.background
                                           : Theme.palette.text
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedTopic = modelData
                                            eventView.model = root.eventsByTopic[modelData] || []
                                        }
                                    }
                                }

                                LogosButton {
                                    text: "×"
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    onClicked: root.removeTopic(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Right: event log + send ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.palette.backgroundSecondary
                radius: Theme.spacing.radiusMedium
                border.width: 1
                border.color: Theme.palette.borderHairline
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.medium
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
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
                            tip: "<b>Event log</b> — every observed event for the selected topic, in order.<br><br>"
                               + "<code>messageReceived</code> — a peer sent us a message on this topic.<br>"
                               + "<code>messageSent</code> — our outgoing message was accepted by the local node.<br>"
                               + "<code>messagePropagated</code> — the message was relayed to the network.<br>"
                               + "<code>messageError</code> — the outgoing message failed.<br>"
                               + "<code>subscribe() returned</code> / <code>send() returned</code> — the immediate return value of the local API call."
                        }
                    }

                    ListView {
                        id: eventView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Theme.spacing.tiny
                        model: []
                        delegate: MessageItem { evt: modelData }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        LogosTextField {
                            id: sendInput
                            placeholderText: root.selectedTopic.length > 0
                                             ? "Message to " + root.selectedTopic
                                             : "Pick a topic first"
                            Layout.fillWidth: true
                            enabled: root.nodeReady && root.selectedTopic.length > 0
                        }
                        Connections {
                            target: sendInput.textInput
                            function onAccepted() { root.sendOutgoing(root.selectedTopic, sendInput.text) }
                        }
                        LogosButton {
                            text: "Send"
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: 40
                            implicitWidth: 88
                            implicitHeight: 40
                            enabled: root.nodeReady
                                     && root.selectedTopic.length > 0
                                     && sendInput.text.length > 0
                            onClicked: root.sendOutgoing(root.selectedTopic, sendInput.text)
                        }
                        InfoChip {
                            tip: "<b>Send</b> calls <code>delivery_module.send(topic, text)</code>.<br><br>"
                               + "On success the <code>LogosResult.getString()</code> value is the <b>request id</b>; "
                               + "the <code>messageSent</code> and <code>messagePropagated</code> events arrive "
                               + "asynchronously and carry the same request id."
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

        LogosText {
            anchors.centerIn: parent
            text: "?"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
        InfoTip {
            visible: infoHover.hovered && tip.length > 0
            text: tip
        }
    }

    // Multi-line tooltip with readable padding, primaryText size, RichText
    // formatting, and a backgroundElevated bubble that pops against the
    // panels. Built from QtQuick.Controls.ToolTip — LogosToolTip's defaults
    // (backgroundSecondary bubble, 60%-opacity bold-everywhere text, ~20px tall)
    // are unreadable against backgroundSecondary panels.
    component InfoTip: ToolTip {
        id: tip

        delay: 200
        timeout: 12000
        leftPadding: Theme.spacing.medium
        rightPadding: Theme.spacing.medium
        topPadding: Theme.spacing.small
        bottomPadding: Theme.spacing.small

        contentItem: Text {
            text: tip.text
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            // Cap long tooltips at ~380px; short tips render at natural width.
            width: implicitWidth > 380 ? 380 : implicitWidth
            font.family: Theme.typography.publicSans
            font.pixelSize: Theme.typography.primaryText
            font.weight: Theme.typography.weightRegular
            color: Theme.palette.text
            lineHeight: 1.35
        }

        background: Rectangle {
            color: Theme.palette.backgroundElevated
            radius: Theme.spacing.radiusSmall
            border.width: 1
            border.color: Theme.palette.border
        }
    }

    // Developer-facing event row. Renders every field of the event verbatim.
    component MessageItem: Rectangle {
        property var evt
        readonly property color accent: {
            if (!evt) return Theme.palette.textSecondary
            switch (evt.eventName) {
                case "messageReceived":    return Theme.palette.info
                case "messageSent":        return Theme.palette.textSecondary
                case "messagePropagated":  return Theme.palette.success
                case "messageError":       return Theme.palette.error
                case "subscribe() returned":
                case "send() returned":    return Theme.palette.primary
            }
            return Theme.palette.textSecondary
        }

        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: rowsCol.implicitHeight + Theme.spacing.medium * 2
        height: implicitHeight
        radius: Theme.spacing.radiusSmall
        color: Theme.palette.backgroundElevated
        border.width: 1
        border.color: Theme.palette.borderHairline

        // Left accent stripe colour-coded by event kind
        Rectangle {
            width: 3
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            color: accent
            radius: Theme.spacing.radiusSmall
        }

        ColumnLayout {
            id: rowsCol
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.medium + 6
            anchors.rightMargin: Theme.spacing.medium
            anchors.topMargin: Theme.spacing.small
            anchors.bottomMargin: Theme.spacing.small
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    text: evt ? evt.eventName : ""
                    font.weight: Theme.typography.weightBold
                    font.pixelSize: Theme.typography.primaryText
                    color: accent
                }
                LogosText {
                    visible: evt && evt.direction
                    text: evt && evt.direction ? "(" + evt.direction + ")" : ""
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                Item { Layout.fillWidth: true }
                LogosText {
                    visible: evt && evt.ts
                    text: evt && evt.ts ? evt.ts : ""
                    font.family: "monospace"
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }

            FieldRow { visible: evt && evt.topic;      name: "topic";      value: evt ? evt.topic       || "" : "" }
            FieldRow { visible: evt && evt.payload;    name: "payload";    value: evt ? evt.payload     || "" : ""; multiline: true }
            FieldRow { visible: evt && evt.hash;       name: "hash";       value: evt ? evt.hash        || "" : ""; mono: true }
            FieldRow { visible: evt && evt.requestId;  name: "requestId";  value: evt ? evt.requestId   || "" : ""; mono: true }
            FieldRow { visible: evt && evt.errorText;  name: "error";      value: evt ? evt.errorText   || "" : ""; isError: true }
        }
    }

    component FieldRow: RowLayout {
        property string name: ""
        property string value: ""
        property bool   mono: false
        property bool   multiline: false
        property bool   isError: false

        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosText {
            text: name + ":"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            Layout.preferredWidth: 72
            Layout.alignment: multiline ? Qt.AlignTop : Qt.AlignVCenter
        }
        LogosText {
            text: value
            font.pixelSize: Theme.typography.primaryText
            font.family: mono ? "monospace" : Theme.typography.publicSans
            color: isError ? Theme.palette.error : Theme.palette.text
            wrapMode: multiline ? Text.WrapAnywhere : Text.NoWrap
            elide: multiline ? Text.ElideNone : Text.ElideMiddle
            Layout.fillWidth: true
        }
    }
}

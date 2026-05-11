import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root

    readonly property var backend: logos.module("logos_delivery_demo")

    // Single global event log. Each entry is an observed event:
    //   { eventName, direction, topic, payload, hash, requestId, errorText, ts }
    property var events: []

    readonly property string nodeStatus:    backend ? backend.connectionStatus : "no backend"
    readonly property bool   nodeReady:     backend ? backend.nodeReady       : false
    readonly property string peerIdValue:   backend ? backend.peerId          : ""
    readonly property int    peerCountValue: backend ? backend.peerCount      : 0
    readonly property string lastErrorValue: backend ? backend.lastError      : ""

    Connections {
        target: backend
        ignoreUnknownSignals: true

        function onMessageReceived(topic, payload, messageHash, timestamp) {
            root.logEvent({
                eventName: "messageReceived",
                direction: "in",
                topic: topic,
                payload: payload,
                hash: messageHash,
                ts: timestamp
            })
        }
        function onMessageSentNotif(requestId, messageHash, timestamp) {
            root.logEvent({
                eventName: "messageSent",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                ts: timestamp
            })
        }
        function onMessagePropagatedNotif(requestId, messageHash, timestamp) {
            root.logEvent({
                eventName: "messagePropagated",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                ts: timestamp
            })
        }
        function onMessageErrorNotif(requestId, messageHash, errorText, timestamp) {
            root.logEvent({
                eventName: "messageError",
                direction: "out",
                requestId: requestId,
                hash: messageHash,
                errorText: errorText,
                ts: timestamp
            })
        }
    }

    function logEvent(evt) {
        const next = root.events.slice()
        next.push(evt)
        root.events = next
        // Auto-scroll to the newest entry.
        Qt.callLater(eventView.positionViewAtEnd)
    }

    // ── Method-call invocations (logged as local events) ──────────────────────

    function callSubscribe(topic) {
        if (!topic) return
        logos.watch(backend.subscribe(topic),
            function(errStr) {
                root.logEvent({
                    eventName: "subscribe() returned",
                    direction: "local",
                    topic: topic,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

    function callUnsubscribe(topic) {
        if (!topic) return
        logos.watch(backend.unsubscribe(topic),
            function(errStr) {
                root.logEvent({
                    eventName: "unsubscribe() returned",
                    direction: "local",
                    topic: topic,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

    function callSend(topic, payload) {
        if (!topic || !payload) return
        logos.watch(backend.sendMessage(topic, payload),
            function(requestId) {
                root.logEvent({
                    eventName: "send() returned",
                    direction: "local",
                    topic: topic,
                    payload: payload,
                    requestId: requestId || "(empty — see lastError)"
                })
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

        // ─── Header / health ─────────────────────────────────────────────────
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: "Peer ID:"
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    SelectableValue {
                        text: root.peerIdValue.length > 0
                              ? root.peerIdValue
                              : "(not available yet)"
                        font.family: "monospace"
                        wrapMode: TextEdit.NoWrap
                        clip: true
                        Layout.fillWidth: true
                    }
                    InfoChip {
                        tip: "<b>Peer ID</b> — this node's local libp2p peer identifier.<br><br>"
                           + "Returned by <code>delivery_module.getNodeInfo(\"MyPeerId\")</code>, "
                           + "polled every 3 seconds together with the peer count."
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
                        font.pixelSize: Theme.typography.primaryText
                    }
                }
            }
        }

        // ─── Event log (full width, all topics) ──────────────────────────────
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
                        text: "Event log"
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightBold
                        Layout.fillWidth: true
                    }
                    LogosText {
                        text: root.events.length + " event" + (root.events.length === 1 ? "" : "s")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    InfoChip {
                        tip: "<b>Event log</b> — every observed event in order, across all topics.<br><br>"
                           + "<code>messageReceived</code> — a peer sent us a message.<br>"
                           + "<code>messageSent</code> — our outgoing message was accepted by the local node.<br>"
                           + "<code>messagePropagated</code> — the message was relayed to the network.<br>"
                           + "<code>messageError</code> — the outgoing message failed.<br>"
                           + "<code>subscribe()</code> / <code>unsubscribe()</code> / <code>send() returned</code> — "
                           + "the immediate return value of the local API call (logged here so the demo is a faithful trace)."
                    }
                }

                ListView {
                    id: eventView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.spacing.tiny
                    model: root.events
                    delegate: MessageItem { evt: modelData }
                }
            }
        }

        // ─── Method-call playground ──────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            MethodCall {
                methodName: "subscribe"
                arg1Name: "contentTopic"
                callEnabled: root.nodeReady
                infoTip: "<b>delivery_module.subscribe(contentTopic)</b><br><br>"
                       + "Tell the node to listen for messages on a libp2p pubsub topic.<br>"
                       + "Returns a <code>LogosResult</code>; on success the node will start emitting "
                       + "<code>messageReceived</code> events for that topic."
                onCall: function(arg1, _arg2) { root.callSubscribe(arg1) }
            }

            MethodCall {
                methodName: "unsubscribe"
                arg1Name: "contentTopic"
                callEnabled: root.nodeReady
                infoTip: "<b>delivery_module.unsubscribe(contentTopic)</b><br><br>"
                       + "Stop listening on the given topic. Returns a <code>LogosResult</code>."
                onCall: function(arg1, _arg2) { root.callUnsubscribe(arg1) }
            }

            MethodCall {
                methodName: "send"
                arg1Name: "contentTopic"
                arg2Name: "payload"
                callEnabled: root.nodeReady
                infoTip: "<b>delivery_module.send(contentTopic, payload)</b><br><br>"
                       + "Publish a message. The module base64-encodes the payload internally — "
                       + "pass raw UTF-8 text.<br><br>"
                       + "On success the <code>LogosResult.getString()</code> value is the <b>request id</b>; "
                       + "the <code>messageSent</code> and <code>messagePropagated</code> events arrive "
                       + "asynchronously and carry the same request id."
                onCall: function(arg1, arg2) { root.callSend(arg1, arg2) }
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
    // panels. Built directly on QtQuick.Controls.ToolTip — LogosToolTip's
    // defaults (backgroundSecondary, 60%-opacity bold-everywhere text, ~20px
    // tall) are unreadable against backgroundSecondary panels.
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

    // ── Method-call playground row ────────────────────────────────────────────
    // Renders as:
    //   methodName ( [arg1____], [arg2____] ) [Call] [?]
    // arg2 is optional; if arg2Name is empty, only one field is shown.
    component MethodCall: Rectangle {
        id: mc

        property string methodName: ""
        property string arg1Name: ""
        property string arg2Name: ""
        property string infoTip: ""
        property bool   callEnabled: true

        signal call(string arg1, string arg2)

        readonly property bool hasArg2: arg2Name.length > 0

        Layout.fillWidth: true
        Layout.preferredHeight: row.implicitHeight + Theme.spacing.medium * 2
        color: Theme.palette.backgroundSecondary
        radius: Theme.spacing.radiusMedium
        border.width: 1
        border.color: Theme.palette.borderHairline

        function invoke() {
            if (!mc.callEnabled) return
            mc.call(arg1Field.text, mc.hasArg2 ? arg2Field.text : "")
        }

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.margins: Theme.spacing.medium
            spacing: Theme.spacing.tiny

            LogosText {
                text: mc.methodName
                font.family: "monospace"
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightBold
                color: Theme.palette.primary
            }
            LogosText {
                text: "("
                font.family: "monospace"
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            LogosTextField {
                id: arg1Field
                placeholderText: mc.arg1Name
                Layout.fillWidth: true
                Layout.minimumWidth: 100
            }
            Connections {
                target: arg1Field.textInput
                function onAccepted() { mc.invoke() }
            }
            LogosText {
                visible: mc.hasArg2
                text: ","
                font.family: "monospace"
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            LogosTextField {
                id: arg2Field
                visible: mc.hasArg2
                placeholderText: mc.arg2Name
                Layout.fillWidth: mc.hasArg2
                Layout.minimumWidth: mc.hasArg2 ? 100 : 0
            }
            Connections {
                target: arg2Field.textInput
                enabled: mc.hasArg2
                function onAccepted() { mc.invoke() }
            }
            LogosText {
                text: ")"
                font.family: "monospace"
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            LogosButton {
                text: "Call"
                Layout.preferredWidth: 72
                Layout.preferredHeight: 40
                implicitWidth: 72
                implicitHeight: 40
                enabled: mc.callEnabled
                         && arg1Field.text.length > 0
                         && (!mc.hasArg2 || arg2Field.text.length > 0)
                onClicked: mc.invoke()
            }
            InfoChip { tip: mc.infoTip }
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
                case "unsubscribe() returned":
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
                    text: evt && evt.direction ? "(" + evt.direction + ")" : ""
                    visible: text.length > 0
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                Item { Layout.fillWidth: true }
                SelectableValue {
                    text: evt && evt.ts ? evt.ts : ""
                    visible: text.length > 0
                    font.family: "monospace"
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    wrapMode: TextEdit.NoWrap
                }
            }

            FieldRow { name: "topic";     value: evt ? evt.topic     || "" : "" }
            FieldRow { name: "payload";   value: evt ? evt.payload   || "" : ""; multiline: true }
            FieldRow { name: "hash";      value: evt ? evt.hash      || "" : ""; mono: true }
            FieldRow { name: "requestId"; value: evt ? evt.requestId || "" : ""; mono: true }
            FieldRow { name: "error";     value: evt ? evt.errorText || "" : ""; isError: true }
        }
    }

    component FieldRow: RowLayout {
        property string name: ""
        property string value: ""
        property bool   mono: false
        property bool   multiline: false
        property bool   isError: false

        // Self-hide when the value is empty so events only render fields they
        // actually carry (e.g. messageSent has no topic/payload, subscribe()
        // returned has no error on success).
        visible: value.length > 0
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosText {
            text: name + ":"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            Layout.preferredWidth: 72
            Layout.alignment: multiline ? Qt.AlignTop : Qt.AlignVCenter
        }
        SelectableValue {
            text: value
            font.family: mono ? "monospace" : Theme.typography.publicSans
            color: isError ? Theme.palette.error : Theme.palette.text
            wrapMode: multiline ? TextEdit.WrapAnywhere : TextEdit.NoWrap
            Layout.fillWidth: true
        }
    }

    // Read-only TextEdit styled like LogosText, with mouse/keyboard selection
    // so developers can copy hashes, topics, peer IDs, etc. straight out of
    // the event log.
    component SelectableValue: TextEdit {
        readOnly: true
        selectByMouse: true
        selectByKeyboard: true
        persistentSelection: true
        textFormat: TextEdit.PlainText
        font.family: Theme.typography.publicSans
        font.pixelSize: Theme.typography.primaryText
        color: Theme.palette.text
        selectionColor: Theme.palette.primary
        selectedTextColor: Theme.palette.background
        // QtQuick.Controls cursor flash blends into a dark theme — turn it off
        // since the field is read-only anyway.
        cursorVisible: false
    }
}

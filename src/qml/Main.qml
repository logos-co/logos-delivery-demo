import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root

    readonly property var backend: logos.module("logos_delivery_demo")

    // Monospace family for code-like values (peer ids, hashes, topics,
    // payloads, request ids, timestamps, method signatures). The design system
    // ships no mono token, so centralise the generic family here — Qt maps
    // "monospace" to the platform's fixed-pitch font.
    readonly property string monoFont: "monospace"

    // The deployed Logos testnet RLN registry — the CAIP-10 account id of the
    // registration program's config PDA, the same one logos-rln-membership-ui
    // registers against.
    readonly property string defaultRegistryId:
        "logos:testnet:ffa111d7384f0f78d1b0927d38a5c34b6a7d11508cf327cc210610c43e43a219"
    // This demo's application id: sha256("logos-delivery-demo"). Any 32 bytes
    // work, but every node that must validate each other's proofs has to share
    // the value — it is bound into the external nullifier.
    readonly property string defaultRlnIdentifier:
        "3a1ae1c9f13a7384d4f32d417c045d50e8eeada9ad6c74bb7022085c123bf824"
    // Required, not optional: liblogos_rln_module.start() rejects a config
    // without it, so a blank field fails the call.
    readonly property string defaultEpochSizeSec: "120"

    // Global payload format, driven by the header dropdown. Payloads cross the
    // backend boundary and live in the event log canonically as space-separated
    // hex; UTF-8 is an alternate *view* of the same bytes, applied when reading
    // the send/channelSend input and when rendering payload fields in the log —
    // so switching the dropdown re-renders payloads already logged.
    readonly property bool utf8Payloads: payloadFormatBox.currentIndex === 1

    // Single global event log. Each entry is an observed event:
    //   { eventName, direction, config, topic, payload, hash, requestId, errorText, ts }
    property var events: []

    readonly property string nodeStatus:    backend ? backend.connectionStatus : "no backend"
    readonly property bool   nodeReady:     backend ? backend.nodeReady       : false
    readonly property string peerIdValue:   backend ? backend.peerId          : ""
    readonly property string multiaddrsValue: backend ? backend.multiaddrs   : ""
    readonly property string lastErrorValue: backend ? backend.lastError      : ""
    readonly property string deliveryVersionValue: backend ? backend.deliveryVersion : ""

    readonly property bool   rlnConfiguredValue: backend ? backend.rlnConfigured : false
    readonly property string rlnMembershipStateValue: backend ? backend.rlnMembershipState : ""
    readonly property string rlnMembershipHashValue: backend ? backend.rlnMembershipHash : ""
    readonly property int    rlnRateLimitValue: backend ? backend.rlnRateLimit : 0
    readonly property int    rlnRemainingValue: backend ? backend.rlnRemaining : -1
    readonly property string rlnEpochIndexValue: backend ? backend.rlnEpochIndex : ""
    readonly property int    rlnEpochSizeSecValue: backend ? backend.rlnEpochSizeSec : 0
    readonly property string rlnStatusValue: backend ? backend.rlnStatus : ""
    readonly property int    rlnProofsValue: backend ? backend.rlnProofs : 0
    readonly property int    rlnValidationsValue: backend ? backend.rlnValidations : 0

    // Seconds left in the current epoch, ticked locally: the boundary is
    // derived from the wall clock the same way the module derives it, so the
    // countdown needs no extra backend round-trip.
    property int epochSecondsLeft: 0
    Timer {
        running: root.rlnConfiguredValue && root.rlnEpochSizeSecValue > 0
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const size = root.rlnEpochSizeSecValue
            root.epochSecondsLeft = size - (Math.floor(Date.now() / 1000) % size)
        }
    }

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
        function onChannelMessageReceived(channelId, senderId, payload, timestamp) {
            root.logEvent({
                eventName: "channelMessageReceived",
                direction: "in",
                channelId: channelId,
                senderId: senderId,
                payload: payload,
                ts: timestamp
            })
        }
        function onChannelMessageSentNotif(channelId, requestId, timestamp) {
            root.logEvent({
                eventName: "channelMessageSent",
                direction: "out",
                channelId: channelId,
                requestId: requestId,
                ts: timestamp
            })
        }
        function onChannelMessageErrorNotif(channelId, requestId, errorText, timestamp) {
            root.logEvent({
                eventName: "channelMessageError",
                direction: "out",
                channelId: channelId,
                requestId: requestId,
                errorText: errorText,
                ts: timestamp
            })
        }
        function onConnectionStateChangedNotif(connectionStatus, timestamp) {
            root.logEvent({
                eventName: "connectionStateChanged",
                direction: "in",
                result: connectionStatus,
                ts: timestamp
            })
        }
        // The node's lifecycle events. On a shared node these fire for another
        // module's createNode/start too, so the log shows the whole node's life.
        function onNodeStartedNotif(success, message, timestamp) {
            root.logEvent({
                eventName: "nodeStarted",
                direction: "in",
                result: success ? "success" : "failed",
                errorText: success ? "" : message,
                ts: timestamp
            })
        }
        function onRlnProofRequested(signalHex, epochTimestamp, timestamp) {
            root.logEvent({
                eventName: "rlnGenerateProof",
                direction: "out",
                hash: signalHex,
                result: "epoch ts " + epochTimestamp,
                ts: timestamp
            })
        }
        function onRlnValidationRequested(signalHex, epochTimestamp, timestamp) {
            root.logEvent({
                eventName: "rlnValidateProof",
                direction: "in",
                hash: signalHex,
                result: "epoch ts " + epochTimestamp,
                ts: timestamp
            })
        }
        function onRlnMembershipTransition(membershipHash, state, previous) {
            root.logEvent({
                eventName: "rlnMembershipStateChanged",
                direction: "in",
                hash: membershipHash,
                result: previous + " \u2192 " + state,
                ts: Date.now()
            })
        }
        function onNodeStoppedNotif(success, message, timestamp) {
            root.logEvent({
                eventName: "nodeStopped",
                direction: "in",
                result: success ? "success" : "failed",
                errorText: success ? "" : message,
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

    // Event timestamps arrive as a qint64 of nanoseconds since the Unix epoch.
    // Convert to milliseconds for a JS Date and render as readable local time.
    // (ns exceeds JS's safe-integer range, but ms is comfortably within it and
    //  the lost sub-millisecond precision doesn't matter for display.)
    function formatTs(ts) {
        if (!ts) return ""
        return Qt.formatDateTime(new Date(Math.floor(ts / 1000000)), "yyyy-MM-dd hh:mm:ss.zzz")
    }

    // ── Payload format conversion ─────────────────────────────────────────────
    // The QML JS engine has no TextEncoder/TextDecoder, so UTF-8 is done by
    // hand. Hex is the canonical form throughout; these only run at the edges.

    // Encode text as UTF-8 bytes rendered as space-separated hex — the form
    // the backend expects.
    function utf8ToHex(text) {
        const bytes = []
        for (let i = 0; i < text.length; i++) {
            const cp = text.codePointAt(i)
            if (cp > 0xFFFF) i++  // skip the low surrogate of an astral pair
            if (cp < 0x80) bytes.push(cp)
            else if (cp < 0x800) bytes.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
            else if (cp < 0x10000) bytes.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
            else bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
        }
        return bytes.map(b => (b < 16 ? "0" : "") + b.toString(16)).join(" ")
    }

    // Decode a (space-separated) hex byte string as UTF-8 text. Payloads are
    // arbitrary bytes, so invalid or truncated sequences decode to U+FFFD
    // instead of breaking the log.
    function hexToUtf8(hex) {
        const clean = hex.replace(/[^0-9a-fA-F]/g, "")
        const bytes = []
        for (let i = 0; i + 1 < clean.length; i += 2)
            bytes.push(parseInt(clean.substring(i, i + 2), 16))
        let out = ""
        let i = 0
        while (i < bytes.length) {
            const b = bytes[i]
            let cp = 0
            let extra = 0
            if (b < 0x80) { cp = b }
            else if ((b & 0xE0) === 0xC0) { cp = b & 0x1F; extra = 1 }
            else if ((b & 0xF0) === 0xE0) { cp = b & 0x0F; extra = 2 }
            else if ((b & 0xF8) === 0xF0) { cp = b & 0x07; extra = 3 }
            else { out += "�"; i++; continue }
            if (i + extra >= bytes.length) { out += "�"; i++; continue }
            let ok = true
            for (let k = 1; k <= extra; k++) {
                const c = bytes[i + k]
                if ((c & 0xC0) !== 0x80) { ok = false; break }
                cp = (cp << 6) | (c & 0x3F)
            }
            if (!ok || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
                out += "�"
                i++
                continue
            }
            out += String.fromCodePoint(cp)
            i += extra + 1
        }
        return out
    }

    // Payload input field → canonical hex for the backend and the event log.
    function encodePayload(input) {
        return utf8Payloads ? utf8ToHex(input) : input
    }

    // Canonical hex from an event → the selected display format.
    function formatPayload(hex) {
        return utf8Payloads ? hexToUtf8(hex) : hex
    }

    // ── Method-call invocations (logged as local events) ──────────────────────

    function callConfigureRln(registryId, rlnIdentifier, epochSizeSec) {
        if (!registryId || !rlnIdentifier) return
        logos.watch(backend.configureRln(registryId, rlnIdentifier, epochSizeSec),
            function(errStr) {
                root.logEvent({
                    eventName: "configureRln() returned",
                    direction: "local",
                    config: registryId + " / " + rlnIdentifier,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

    function callCreateNode(preset, mode, anonymity) {
        if (!preset || !mode || !anonymity) return
        logos.watch(backend.createNode(preset, mode, anonymity),
            function(errStr) {
                root.logEvent({
                    eventName: "createNode() returned",
                    direction: "local",
                    config: preset + " / " + mode + " / " + anonymity,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

    function callCreateNodeWithConfig(configJson) {
        if (!configJson) return
        logos.watch(backend.createNodeWithConfig(configJson),
            function(errStr) {
                root.logEvent({
                    eventName: "createNode() returned",
                    direction: "local",
                    config: configJson,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

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

    function callChannelCreate(channelId, contentTopic, senderId) {
        if (!channelId || !contentTopic || !senderId) return
        logos.watch(backend.channelCreate(channelId, contentTopic, senderId),
            function(errStr) {
                root.logEvent({
                    eventName: "channelCreate() returned",
                    direction: "local",
                    channelId: channelId,
                    topic: contentTopic,
                    senderId: senderId,
                    errorText: errStr || ""
                })
            },
            function(_e) {}
        )
    }

    function callChannelExists(channelId) {
        if (!channelId) return
        logos.watch(backend.channelExists(channelId),
            function(result) {
                root.logEvent({
                    eventName: "channelExists() returned",
                    direction: "local",
                    channelId: channelId,
                    result: result || "(empty — see lastError)"
                })
            },
            function(_e) {}
        )
    }

    function callChannelSend(channelId, payload) {
        if (!channelId || !payload) return
        logos.watch(backend.channelSend(channelId, payload),
            function(requestId) {
                root.logEvent({
                    eventName: "channelSend() returned",
                    direction: "local",
                    channelId: channelId,
                    payload: payload,
                    requestId: requestId || "(empty — see lastError)"
                })
            },
            function(_e) {}
        )
    }

    function callChannelClose(channelId) {
        if (!channelId) return
        logos.watch(backend.channelClose(channelId),
            function(errStr) {
                root.logEvent({
                    eventName: "channelClose() returned",
                    direction: "local",
                    channelId: channelId,
                    errorText: errStr || ""
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

                    SelectableValue {
                        text: "logos-delivery " + root.deliveryVersionValue
                        visible: root.deliveryVersionValue.length > 0
                        font.family: root.monoFont
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        wrapMode: TextEdit.NoWrap
                    }
                    InfoChip {
                        visible: root.deliveryVersionValue.length > 0
                        tip: "<b>logos-delivery version</b> — the version string of the "
                           + "<code>liblogosdelivery</code> library backing the module.<br><br>"
                           + "Read once after the node starts via "
                           + "<code>delivery_module.getNodeInfo(\"Version\")</code> "
                           + "(the same call the module's own <code>version()</code> wraps)."
                    }

                    Item { Layout.fillWidth: true }

                    LogosBadge {
                        text: root.nodeReady ? root.nodeStatus : "no node — call createNode"
                        // Health from the node's connectionStateChanged event:
                        // Connected → green, PartiallyConnected → yellow,
                        // Disconnected → red; anything else (e.g. before the
                        // node exists) is neutral.
                        color: !root.nodeReady                              ? Theme.palette.textSecondary
                             : root.nodeStatus === "Connected"             ? Theme.palette.success
                             : root.nodeStatus === "PartiallyConnected"    ? Theme.palette.warning
                             : root.nodeStatus === "Disconnected"          ? Theme.palette.error
                             :                                               Theme.palette.textSecondary
                    }
                    InfoChip {
                        tip: "<b>Connection status</b> — the node's health, surfaced from "
                           + "<code>delivery_module</code>'s <code>connectionStateChanged</code> "
                           + "event. Possible states:<br><br>"
                           + "<code>Connected</code> — healthy relay connectivity "
                           + "(green).<br>"
                           + "<code>PartiallyConnected</code> — connected to some peers but "
                           + "below the healthy relay threshold (yellow).<br>"
                           + "<code>Disconnected</code> — no usable relay connectivity "
                           + "(red).<br><br>"
                           + "Until a node exists the badge reads "
                           + "<i>no node — call createNode</i>.<br><br>"
                           + "The event fires on transitions only, so a node that was "
                           + "already running when this view opened shows no status until "
                           + "its next change (logos-delivery-module#81 tracks a queryable "
                           + "status). Every event is also logged above."
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
                    // fillWidth capped at implicitWidth: the value takes only
                    // its natural width — keeping the info chip attached right
                    // after the text — but can still shrink (clipped) when the
                    // window is narrow.
                    SelectableValue {
                        text: root.peerIdValue.length > 0
                              ? root.peerIdValue
                              : "(not available yet)"
                        font.family: root.monoFont
                        wrapMode: TextEdit.NoWrap
                        clip: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                    }
                    InfoChip {
                        tip: "<b>Peer ID</b> — this node's local libp2p peer identifier.<br><br>"
                           + "Returned by <code>delivery_module.getNodeInfo(\"MyPeerId\")</code>. "
                           + "Fixed for the life of the node, so it is read once — when this "
                           + "view opens and on the node's <code>nodeStarted</code> event — "
                           + "rather than polled. That read is also what tells the demo "
                           + "whether a node exists at all, whichever module created it."
                    }

                    Item { Layout.fillWidth: true }

                    LogosText {
                        text: "Payload format:"
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    LogosComboBox {
                        id: payloadFormatBox
                        model: ["HEX", "UTF-8"]
                        currentIndex: 0
                        Layout.preferredWidth: 110
                    }
                    InfoChip {
                        tip: "<b>Payload format</b> — global setting for how message payloads "
                           + "are entered and displayed.<br><br>"
                           + "<code>HEX</code> — payloads are typed and shown as hex bytes, "
                           + "e.g. <code>48 65 6c 6c 6f</code>.<br>"
                           + "<code>UTF-8</code> — payloads are typed as plain text (encoded to "
                           + "UTF-8 bytes before sending) and event payloads are decoded as "
                           + "UTF-8 for display; bytes that aren't valid UTF-8 render as "
                           + "<code>�</code>.<br><br>"
                           + "This is purely a demo feature, <b>not</b> part of the "
                           + "<code>logos-delivery-module</code> API — the module always treats "
                           + "the payload as pure bytes. Switching re-renders payloads already "
                           + "in the event log, but text already typed in a payload field is "
                           + "reinterpreted, not converted."
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: "Multiaddr:"
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    SelectableValue {
                        text: root.multiaddrsValue.length > 0
                              ? root.multiaddrsValue
                              : "(not available yet)"
                        font.family: root.monoFont
                        wrapMode: TextEdit.NoWrap
                        clip: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                    }
                    InfoChip {
                        tip: "<b>Multiaddr</b> — every address this node listens on, as the "
                           + "verbatim <code>getNodeInfo(\"MyMultiaddresses\")</code> string.<br><br>"
                           + "Read once per node, alongside the peer id.<br><br>"
                           + "Paste one into another node's <code>entry-node</code> config to "
                           + "peer two local nodes directly instead of bootstrapping off a "
                           + "fleet — see the advanced <code>createNode</code> config."
                    }

                    Item { Layout.fillWidth: true }

                    LogosSwitch {
                        id: advancedNodeConfig
                        visible: !root.nodeReady
                        text: "Advanced config"
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    InfoChip {
                        visible: !root.nodeReady
                        tip: "<b>Advanced node config</b> — swaps <code>createNode</code>'s three "
                           + "dropdowns for the raw config.<br><br>"
                           + "The dropdowns only reach <code>preset</code>, <code>mode</code> "
                           + "and <code>anonymityLevel</code>. The config itself passes through "
                           + "to logos-delivery verbatim, which owns the grammar — so writing it "
                           + "directly reaches everything else: <code>entry-node</code> to peer "
                           + "with a local node instead of a fleet, <code>cluster-id</code>, "
                           + "ports, or an <code>entryLayer</code> below the default "
                           + "<code>channels</code>.<br><br>"
                           + "Checked for well-formed JSON here; every other error comes back "
                           + "from logos-delivery."
                    }
                }

                Rectangle {
                    visible: root.lastErrorValue.length > 0
                    Layout.fillWidth: true
                    // Grows past the one-line 28px so long errors wrap instead
                    // of being cut off at the border.
                    Layout.preferredHeight: Math.max(28, lastErrorText.implicitHeight + Theme.spacing.small * 2)
                    radius: Theme.spacing.radiusSmall
                    color: Qt.rgba(Theme.palette.error.r, Theme.palette.error.g, Theme.palette.error.b, 0.15)
                    border.width: 1
                    border.color: Theme.palette.error
                    LogosText {
                        id: lastErrorText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacing.small
                        anchors.rightMargin: Theme.spacing.small
                        wrapMode: Text.Wrap
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
                    }
                    InfoChip {
                        tip: "<b>Event log</b> — every observed event in order, across all topics.<br><br>"
                           + "<code>messageReceived</code> — a peer sent us a message.<br>"
                           + "<code>messageSent</code> — our outgoing message was accepted by the local node.<br>"
                           + "<code>messagePropagated</code> — the message was relayed to the network.<br>"
                           + "<code>messageError</code> — the outgoing message failed.<br>"
                           + "<code>channelMessageReceived</code> — a peer sent us a message on a reliable channel.<br>"
                           + "<code>channelMessageSent</code> — every segment of a channel send was confirmed.<br>"
                           + "<code>channelMessageError</code> — a channel send finalised with a failed segment.<br>"
                           + "<code>createNode()</code> / <code>subscribe()</code> / <code>unsubscribe()</code> / <code>send()</code> / "
                           + "<code>channelCreate()</code> / <code>channelExists()</code> / <code>channelSend()</code> / <code>channelClose() returned</code> — "
                           + "the immediate return value of the local API call (logged here so the demo is a faithful trace)."
                    }

                    Item { Layout.fillWidth: true }

                    LogosText {
                        text: root.events.length + " event" + (root.events.length === 1 ? "" : "s")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    DemoButton {
                        text: "Clear"
                        enabled: root.events.length > 0
                        // LogosButton floors implicitWidth at 100 and pads
                        // spacing.large a side, which elides a short label.
                        leftPadding: Theme.spacing.small
                        rightPadding: Theme.spacing.small
                        implicitWidth: implicitContentWidth + leftPadding + rightPadding
                        implicitHeight: 28
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: 28
                        onClicked: root.events = []
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
        // Configuring the node and using it are disjoint phases — every
        // configuration call is refused once the node exists, every API call
        // before it — so only the panels of the current phase are shown.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            ApiGroup {
                title: "Configuration"
                visible: !root.nodeReady
                Layout.fillWidth: true

                MethodCall {
                    methodName: "configureRln"
                    arg1Name: "registryId"
                    arg2Name: "rlnIdentifier"
                    arg3Name: "epochSizeSec"
                    arg1Default: root.defaultRegistryId
                    arg2Default: root.defaultRlnIdentifier
                    arg3Default: root.defaultEpochSizeSec
                    callEnabled: root.backend && !root.nodeReady
                    infoTip: "<b>delivery_module.configureRln(config)</b><br><br>"
                           + "Turn RLN on for the node this demo is about to create.<br>"
                           + "<b>registryId</b> — CAIP-10 account id of the registry "
                           + "deployment, e.g. <code>logos:testnet:0</code>.<br>"
                           + "<b>rlnIdentifier</b> — per-application id, exactly 64 hex "
                           + "characters (32 bytes); every node of a deployment must use "
                           + "the same one.<br>"
                           + "<b>epochSizeSec</b> — the application's rate-limit epoch "
                           + "in seconds. Required: the RLN module rejects a start config "
                           + "without it, and every proof generator and verifier of a "
                           + "deployment must share the value.<br><br>"
                           + "All three are prefilled with this demo's defaults — the "
                           + "deployed testnet registry, this demo's own application id, "
                           + "and a 120 s epoch.<br><br>"
                           + "Module-only: the delivery library's RLN plugin is "
                           + "implementation-agnostic — it names no registry and carries no "
                           + "config — so this is the one place a membership is named. It "
                           + "never rides the <code>createNode</code> config.<br><br>"
                           + "Must be called <i>before</i> <code>createNode()</code>: an "
                           + "installed plugin is what makes the library mount RLN, and it "
                           + "reads that at node creation. Without this call the node comes "
                           + "up with RLN off.<br><br>"
                           + "The node's membership must already be active — registration "
                           + "happens out of band, through the RLN module. Without one, "
                           + "<code>createNode</code> fails at start."
                    onCall: function(arg1, arg2, arg3) { root.callConfigureRln(arg1, arg2, arg3) }
                }

                CreateNodeCall {
                    visible: !advancedNodeConfig.checked
                    callEnabled: root.backend && !root.nodeReady
                    infoTip: "<b>delivery_module.createNode(config)</b> + <b>start()</b><br><br>"
                           + "Create and start the node against a chosen network.<br>"
                           + "<b>preset</b> — <code>logos.dev</code> (Logos Dev Network) or "
                           + "<code>logos.test</code> (Logos Test Network); both auto-configure "
                           + "cluster id, entry nodes, sharding and RLN.<br>"
                           + "<b>mode</b> — <code>Core</code> (full relay node) or "
                           + "<code>Edge</code> (light/edge node).<br>"
                           + "<b>anonymityLevel</b> — sender anonymity through mix: "
                           + "<code>None</code> (send directly), <code>Preferred</code> or "
                           + "<code>Required</code>; anything above <code>None</code> mounts mix "
                           + "and sends over it.<br><br>"
                           + "The node is no longer started automatically, so you can exercise "
                           + "the module against different fleets and modes.<br><br>"
                           + "Can be called once per Logos Core instance: <code>delivery_module</code> "
                           + "and its node are a singleton shared by every module. If another "
                           + "module (e.g. chat) created the node, this call is disabled and the "
                           + "preset/mode chosen there apply — the demo just uses that node."
                    onCall: function(preset, mode, anonymity) { root.callCreateNode(preset, mode, anonymity) }
                }

                MethodCall {
                    visible: advancedNodeConfig.checked
                    methodName: "createNode"
                    arg1Name: "config (JSON)"
                    callEnabled: root.backend && !root.nodeReady
                    infoTip: "<b>delivery_module.createNode(config)</b> + <b>start()</b><br><br>"
                           + "The config logos-delivery actually receives, written out in "
                           + "full.<br><br>"
                           + "Full stack against a fleet:<br>"
                           + "<code>{\"mode\":\"Core\",\"preset\":\"logos.test\"}</code><br><br>"
                           + "Peered with a local node instead of a fleet — take the address "
                           + "from that node's <b>Multiaddr</b> in the header:<br>"
                           + "<code>{\"mode\":\"Core\",\"preset\":\"logos.test\","
                           + "\"messagingOverrides\":{\"entry-node\":[\"/ip4/127.0.0.1/tcp/…\"]}}</code>"
                           + "<br><br>"
                           + "<code>messagingOverrides</code> takes the messaging layer's conf "
                           + "keys by their serialized names — <code>entry-node</code>, "
                           + "<code>cluster-id</code>, <code>tcp-port</code>, "
                           + "<code>discv5-udp-port</code> — plus <code>anonymityLevel</code>."
                    onCall: function(arg1, _arg2, _arg3) { root.callCreateNodeWithConfig(arg1) }
                }
            }

            ApiGroup {
                title: "RLN"
                visible: root.rlnConfiguredValue
                Layout.fillWidth: true

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: Theme.spacing.medium
                    rowSpacing: Theme.spacing.small

                    RlnStat {
                        label: "Membership"
                        value: root.rlnMembershipStateValue.length > 0
                               ? root.rlnMembershipStateValue : "reading…"
                        // Only active and grace_period can generate a proof.
                        highlight: root.rlnMembershipStateValue === "active"
                                   || root.rlnMembershipStateValue === "grace_period"
                                 ? Theme.palette.success
                                 : root.rlnMembershipStateValue === "pending"
                                 ? Theme.palette.warning
                                 : root.rlnMembershipStateValue.length > 0
                                 ? Theme.palette.error
                                 : Theme.palette.textSecondary
                        tip: "<b>liblogos_rln_module.get_membership_state(registryId, rlnIdentifier)</b>"
                           + "<br><br>The membership backing this scope, re-read every 10 s and "
                           + "immediately on the module's <code>membership_state_changed</code> "
                           + "push.<br><br>"
                           + "<code>active</code> / <code>grace_period</code> can generate proofs; "
                           + "<code>pending</code> is a submitted registration still confirming; "
                           + "<code>unknown</code> means no membership resolves for the scope, and "
                           + "<code>createNode</code> will fail at start.<br><br>"
                           + "Registration happens out of band, in the RLN membership UI — never "
                           + "through this demo."
                    }

                    RlnStat {
                        label: "Messages left this epoch"
                        value: root.rlnRemainingValue < 0
                               ? "—"
                               : root.rlnRemainingValue + " / " + root.rlnRateLimitValue
                        highlight: root.rlnRemainingValue < 0    ? Theme.palette.textSecondary
                                 : root.rlnRemainingValue === 0  ? Theme.palette.error
                                 : root.rlnRemainingValue <= Math.max(1, root.rlnRateLimitValue / 10)
                                                                 ? Theme.palette.warning
                                 :                                 Theme.palette.success
                        tip: "<b>liblogos_rln_module.get_epoch_quota(registryId, rlnIdentifier, "
                           + "timestamp)</b><br><br>"
                           + "The budget still unspent in the current epoch over this "
                           + "membership's rate limit. Polled every 2 s, and again on every proof "
                           + "the node generates.<br><br>"
                           + "Purely local — no registry read. Advisory: "
                           + "<code>generate_proof</code> stays the allocation authority, so a "
                           + "send can still come back <code>budget_exhausted</code> if the "
                           + "budget went between this read and the proof.<br><br>"
                           + "A rate limit of <code>0</code> always means no usable membership, "
                           + "never an exhausted budget."
                    }

                    RlnStat {
                        label: "Epoch"
                        value: root.rlnEpochIndexValue.length > 0
                               ? root.rlnEpochIndexValue + "  (" + root.epochSecondsLeft + "s left)"
                               : "—"
                        tip: "<b>Epoch</b> — <code>floor(timestamp / epochSizeSec)</code>, the "
                           + "index the module encodes into every proof's external nullifier.<br><br>"
                           + "The countdown to the next boundary is computed locally from the "
                           + "same wall clock, so it needs no backend call. The budget resets "
                           + "when it wraps.<br><br>"
                           + "Epoch size came from <code>configureRln</code>: "
                           + "<code>" + root.rlnEpochSizeSecValue + " s</code>."
                    }

                    RlnStat {
                        label: "Proofs / validations"
                        value: root.rlnProofsValue + " / " + root.rlnValidationsValue
                        tip: "<b>delivery_module</b> RLN request events — "
                           + "<code>dispatchRlnGenerateProofRequestEvent</code> and "
                           + "<code>dispatchRlnValidateProofRequestEvent</code>.<br><br>"
                           + "One proof per outbound message, one validation per inbound one, "
                           + "counted since this view opened. Each is also a line in the event "
                           + "log above.<br><br>"
                           + "The delivery library asks an external RLN module for every RLN "
                           + "operation; these events fire even though the module's in-process "
                           + "bridge is what answers them."
                    }
                }

                RowLayout {
                    visible: root.rlnStatusValue.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: root.rlnStatusValue
                        color: Theme.palette.error
                        font.pixelSize: Theme.typography.secondaryText
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    visible: root.rlnMembershipHashValue.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: "Membership:"
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    SelectableValue {
                        text: root.rlnMembershipHashValue
                        font.family: root.monoFont
                        wrapMode: TextEdit.NoWrap
                        clip: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            SplitView {
                id: apiSplit

                visible: root.nodeReady
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(messagingGroup.implicitHeight,
                                                 channelsGroup.implicitHeight)
                orientation: Qt.Horizontal

                // SplitHandle attached properties live on the delegate root,
                // so the inner line reaches them through handleRoot's id.
                handle: Rectangle {
                    id: handleRoot
                    implicitWidth: Theme.spacing.small
                    implicitHeight: Theme.spacing.small
                    color: "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        visible: handleRoot.SplitHandle.pressed || handleRoot.SplitHandle.hovered
                        width: handleRoot.SplitHandle.pressed ? 3 : 1
                        height: parent.height
                        radius: 1
                        color: handleRoot.SplitHandle.pressed ? Theme.palette.primary
                             :                                  Theme.palette.border
                    }
                }

                ApiGroup {
                    id: messagingGroup
                    title: "Messaging"
                    tag: "Beta"
                    SplitView.preferredWidth: apiSplit.width / 2
                    SplitView.minimumWidth: 280

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
                               + "Stop listening on the given topic. Returns a <code>LogosResult</code>.<br><br>"
                               + "Subscriptions are node-wide and shared with every module "
                               + "using <code>delivery_module</code> — unsubscribing a topic "
                               + "another module (e.g. chat) relies on stops its delivery too."
                        onCall: function(arg1, _arg2) { root.callUnsubscribe(arg1) }
                    }

                    MethodCall {
                        methodName: "send"
                        arg1Name: "contentTopic"
                        arg2Name: root.utf8Payloads ? "payload (UTF-8 text)" : "payload (hex)"
                        callEnabled: root.nodeReady
                        infoTip: "<b>delivery_module.send(contentTopic, payload)</b><br><br>"
                               + "Publish a message. The payload is raw <b>bytes</b> — enter it "
                               + "in the format selected in the header: hex "
                               + "(e.g. <code>48 65 6c 6c 6f</code> or <code>48656c6c6f</code>) "
                               + "or UTF-8 text, encoded to bytes before sending.<br><br>"
                               + "On success the <code>LogosResult.getString()</code> value is the <b>request id</b>; "
                               + "the <code>messageSent</code> and <code>messagePropagated</code> events arrive "
                               + "asynchronously and carry the same request id."
                        onCall: function(arg1, arg2) { root.callSend(arg1, root.encodePayload(arg2)) }
                    }
                }

                ApiGroup {
                    id: channelsGroup
                    title: "Reliable Channels"
                    tag: "Developer Preview"
                    SplitView.fillWidth: true
                    SplitView.minimumWidth: 320

                    MethodCall {
                        methodName: "channelCreate"
                        arg1Name: "channelId"
                        arg2Name: "contentTopic"
                        arg3Name: "senderId"
                        callEnabled: root.nodeReady
                        infoTip: "<b>delivery_module.channelCreate(channelId, contentTopic, senderId)</b><br><br>"
                               + "Create (or re-open) a <b>reliable channel</b> on a content topic.<br>"
                               + "<b>channelId</b> — application-chosen channel identifier; both peers "
                               + "must use the same id.<br>"
                               + "<b>contentTopic</b> — the content topic the channel communicates on.<br>"
                               + "<b>senderId</b> — this participant's SDS (Scalable Data Sync) sender "
                               + "identifier; any string unique per participant (e.g. your peer id).<br><br>"
                               + "Persisted channel state survives <code>channelClose()</code>, so "
                               + "re-creating a channel with the same id restores it."
                        onCall: function(arg1, arg2, arg3) { root.callChannelCreate(arg1, arg2, arg3) }
                    }

                    MethodCall {
                        methodName: "channelExists"
                        arg1Name: "channelId"
                        callEnabled: root.nodeReady
                        infoTip: "<b>delivery_module.channelExists(channelId)</b><br><br>"
                               + "Check whether a reliable channel is currently open. An unknown "
                               + "channel id is not an error.<br><br>"
                               + "Returns <code>\"true\"</code> or <code>\"false\"</code> (the verbatim "
                               + "FFI string), logged as the <code>result</code> field."
                        onCall: function(arg1, _arg2) { root.callChannelExists(arg1) }
                    }

                    MethodCall {
                        methodName: "channelSend"
                        arg1Name: "channelId"
                        arg2Name: root.utf8Payloads ? "payload (UTF-8 text)" : "payload (hex)"
                        callEnabled: root.nodeReady
                        infoTip: "<b>delivery_module.channelSend(channelId, payload)</b><br><br>"
                               + "Send a message on a reliable channel. The payload is raw "
                               + "<b>bytes</b> — enter it in the format selected in the header: "
                               + "hex (e.g. <code>48 65 6c 6c 6f</code> or <code>48656c6c6f</code>) "
                               + "or UTF-8 text, encoded to bytes before sending.<br><br>"
                               + "On success the <code>LogosResult.getString()</code> value is the <b>request id</b>; "
                               + "<code>channelMessageSent</code> arrives once every segment of the send is "
                               + "confirmed, or <code>channelMessageError</code> if the send finalises with "
                               + "a failed segment — both carry the same request id."
                        onCall: function(arg1, arg2) { root.callChannelSend(arg1, root.encodePayload(arg2)) }
                    }

                    MethodCall {
                        methodName: "channelClose"
                        arg1Name: "channelId"
                        callEnabled: root.nodeReady
                        infoTip: "<b>delivery_module.channelClose(channelId)</b><br><br>"
                               + "Close a reliable channel: stops its SDS loops. Persisted state "
                               + "survives, so <code>channelCreate()</code> with the same id restores "
                               + "the channel.<br><br>"
                               + "Channel ids are node-wide — closing an id another module "
                               + "opened stops that module's channel too."
                        onCall: function(arg1, _arg2) { root.callChannelClose(arg1) }
                    }
                }
            }
        }
    }

    // ── Reusable inline components ────────────────────────────────────────────

    // Keyboard-navigation shims: neither LogosTextField nor LogosButton opts
    // into the Tab chain, and LogosButton has no keyboard activation. Drop
    // these once logos-design-system handles it.

    component DemoTextField: LogosTextField {
        focusPolicy: Qt.StrongFocus
        // Tab lands on the wrapper Control, not the text: forward focus to the
        // inner TextInput whenever the wrapper gains it. Pre-seeding scope
        // focus at completion does not survive to Tab time.
        onActiveFocusChanged: if (activeFocus) textInput.forceActiveFocus()
    }

    component DemoButton: LogosButton {
        id: btn

        focusPolicy: Qt.StrongFocus
        Keys.onReturnPressed: btn.clicked()
        Keys.onEnterPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()

        // LogosButton only highlights on hover/press, so keyboard focus would
        // otherwise be invisible.
        Rectangle {
            anchors.fill: parent
            radius: btn.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.palette.overlayOrange
            visible: btn.visualFocus
        }
    }

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

    // ── API-call group panel ──────────────────────────────────────────────────
    // Children declared inside an ApiGroup land in the inner column below the
    // title; the trailing filler keeps a shorter group's cards packed to the top.
    component ApiGroup: Rectangle {
        id: grp

        property string title: ""
        property string tag: ""
        default property alias content: groupCol.data

        implicitHeight: grpCol.implicitHeight + Theme.spacing.medium * 2
        color: Theme.palette.backgroundSecondary
        radius: Theme.spacing.radiusMedium
        border.width: 1
        border.color: Theme.palette.borderHairline

        ColumnLayout {
            id: grpCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.medium
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                // On top of the column's spacing, so the title sits apart from
                // the cards rather than looking like the first of them.
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    text: grp.title
                    font.pixelSize: Theme.typography.subtitleText
                    font.weight: Theme.typography.weightBold
                }

                Rectangle {
                    visible: grp.tag.length > 0
                    Layout.preferredWidth: tagLabel.implicitWidth + Theme.spacing.small * 2
                    Layout.preferredHeight: tagLabel.implicitHeight + Theme.spacing.tiny * 2
                    radius: height / 2
                    color: Qt.rgba(Theme.palette.textSecondary.r,
                                   Theme.palette.textSecondary.g,
                                   Theme.palette.textSecondary.b, 0.15)
                    border.width: 1
                    border.color: Theme.palette.textSecondary

                    LogosText {
                        id: tagLabel
                        anchors.centerIn: parent
                        text: grp.tag
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }

                Item { Layout.fillWidth: true }
            }

            ColumnLayout {
                id: groupCol
                Layout.fillWidth: true
                spacing: Theme.spacing.small
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ── Method-call playground row ────────────────────────────────────────────
    // Renders as:
    //   methodName ( [arg1____], [arg2____], [arg3____] ) [Call] [?]
    // arg2 and arg3 are optional; fields with an empty name are not shown.
    component MethodCall: Rectangle {
        id: mc

        property string methodName: ""
        property string arg1Name: ""
        property string arg2Name: ""
        property string arg3Name: ""
        property string arg1Default: ""
        property string arg2Default: ""
        property string arg3Default: ""
        property string infoTip: ""
        property bool   callEnabled: true

        signal call(string arg1, string arg2, string arg3)

        readonly property bool hasArg2: arg2Name.length > 0
        readonly property bool hasArg3: arg3Name.length > 0

        Layout.fillWidth: true
        Layout.preferredHeight: row.implicitHeight
        color: "transparent"

        function invoke() {
            if (!mc.callEnabled) return
            mc.call(arg1Field.text,
                    mc.hasArg2 ? arg2Field.text : "",
                    mc.hasArg3 ? arg3Field.text : "")
        }

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: Theme.spacing.tiny

            LogosText {
                text: mc.methodName
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightBold
                color: Theme.palette.primary
            }
            LogosText {
                text: "("
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            // No Layout.minimumWidth: per-field floors add up past the group's
            // width and the row overflows instead of shrinking.
            DemoTextField {
                id: arg1Field
                placeholderText: mc.arg1Name
                text: mc.arg1Default
                Layout.fillWidth: true
            }
            Connections {
                target: arg1Field.textInput
                function onAccepted() { mc.invoke() }
            }
            LogosText {
                visible: mc.hasArg2
                text: ","
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            DemoTextField {
                id: arg2Field
                visible: mc.hasArg2
                placeholderText: mc.arg2Name
                text: mc.arg2Default
                Layout.fillWidth: mc.hasArg2
            }
            Connections {
                target: arg2Field.textInput
                enabled: mc.hasArg2
                function onAccepted() { mc.invoke() }
            }
            LogosText {
                visible: mc.hasArg3
                text: ","
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            DemoTextField {
                id: arg3Field
                visible: mc.hasArg3
                placeholderText: mc.arg3Name
                text: mc.arg3Default
                Layout.fillWidth: mc.hasArg3
            }
            Connections {
                target: arg3Field.textInput
                enabled: mc.hasArg3
                function onAccepted() { mc.invoke() }
            }
            LogosText {
                text: ")"
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
            }
            DemoButton {
                text: "Call"
                Layout.preferredWidth: 72
                Layout.preferredHeight: 40
                implicitWidth: 72
                implicitHeight: 40
                enabled: mc.callEnabled
                         && arg1Field.text.length > 0
                         && (!mc.hasArg2 || arg2Field.text.length > 0)
                         && (!mc.hasArg3 || arg3Field.text.length > 0)
                onClicked: mc.invoke()
            }
            InfoChip { tip: mc.infoTip }
        }
    }

    // One createNode argument: the parameter name above its value picker. The
    // other rows name their arguments through a text field's placeholder, which
    // a combo box has nowhere to put.
    component ArgCombo: ColumnLayout {
        id: argCombo

        property string label: ""
        property alias model: box.model
        readonly property alias currentText: box.currentText
        readonly property alias controlHeight: box.height

        spacing: Theme.spacing.tiny
        Layout.fillWidth: true
        Layout.minimumWidth: 120

        LogosText {
            text: argCombo.label
            font.family: root.monoFont
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosComboBox {
            id: box
            currentIndex: 0
            Layout.fillWidth: true
        }
    }

    // ── createNode playground row ─────────────────────────────────────────────
    // Like MethodCall, but the three arguments are fixed-choice enums, so they
    // are picked from labelled dropdowns rather than typed:
    //   createNode ( [logos.dev ▾], [Core ▾], [None ▾] ) [Call] [?]
    component CreateNodeCall: Rectangle {
        id: cn

        property string infoTip: ""
        property bool   callEnabled: true

        signal call(string preset, string mode, string anonymity)

        Layout.fillWidth: true
        Layout.preferredHeight: cnRow.implicitHeight
        color: "transparent"

        RowLayout {
            id: cnRow
            anchors.fill: parent
            spacing: Theme.spacing.tiny

            LogosText {
                text: "createNode"
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightBold
                color: Theme.palette.primary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: presetBox.controlHeight
            }
            LogosText {
                text: "("
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: presetBox.controlHeight
            }
            ArgCombo {
                id: presetBox
                label: "preset"
                // logos.test is the default fleet.
                model: ["logos.test", "logos.dev"]
                enabled: cn.callEnabled
            }
            LogosText {
                text: ","
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: presetBox.controlHeight
            }
            ArgCombo {
                id: modeBox
                label: "mode"
                model: ["Core", "Edge"]
                enabled: cn.callEnabled
            }
            LogosText {
                text: ","
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: presetBox.controlHeight
            }
            ArgCombo {
                id: anonymityBox
                label: "anonymityLevel"
                model: ["None", "Preferred", "Required"]
                enabled: cn.callEnabled
            }
            LogosText {
                text: ")"
                font.family: root.monoFont
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.textSecondary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: presetBox.controlHeight
            }
            DemoButton {
                text: "Call"
                Layout.preferredWidth: 72
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignBottom
                implicitWidth: 72
                implicitHeight: 40
                enabled: cn.callEnabled
                onClicked: cn.call(presetBox.currentText, modeBox.currentText, anonymityBox.currentText)
            }
            InfoChip {
                tip: cn.infoTip
                Layout.alignment: Qt.AlignBottom
            }
        }
    }

    // Developer-facing event row. Renders every field of the event verbatim.
    component MessageItem: Rectangle {
        property var evt
        readonly property color accent: {
            if (!evt) return Theme.palette.textSecondary
            switch (evt.eventName) {
                case "messageReceived":        return Theme.palette.info
                case "channelMessageReceived": return Theme.palette.info
                case "messageSent":            return Theme.palette.textSecondary
                case "messagePropagated":      return Theme.palette.success
                case "channelMessageSent":     return Theme.palette.success
                case "messageError":           return Theme.palette.error
                case "channelMessageError":    return Theme.palette.error
                case "createNode() returned":
                case "subscribe() returned":
                case "unsubscribe() returned":
                case "send() returned":
                case "channelCreate() returned":
                case "channelExists() returned":
                case "channelSend() returned":
                case "channelClose() returned": return Theme.palette.primary
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
                    text: evt && evt.ts ? root.formatTs(evt.ts) : ""
                    visible: text.length > 0
                    font.family: root.monoFont
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    wrapMode: TextEdit.NoWrap
                }
            }

            FieldRow { name: "config";    value: evt ? evt.config    || "" : ""; mono: true }
            FieldRow { name: "channelId"; value: evt ? evt.channelId || "" : ""; mono: true }
            FieldRow { name: "senderId";  value: evt ? evt.senderId  || "" : ""; mono: true }
            FieldRow { name: "topic";     value: evt ? evt.topic     || "" : ""; mono: true }
            // Events store the payload as hex; render it in the globally
            // selected format. 480 chars of space-separated hex ≈ 160 payload
            // bytes, about two wrapped lines.
            FieldRow { name: "payload";   value: evt && evt.payload ? root.formatPayload(evt.payload) : ""; mono: true; multiline: true; truncateAt: 480 }
            FieldRow { name: "hash";      value: evt ? evt.hash      || "" : ""; mono: true }
            FieldRow { name: "requestId"; value: evt ? evt.requestId || "" : ""; mono: true }
            FieldRow { name: "result";    value: evt ? evt.result    || "" : ""; mono: true }
            FieldRow { name: "error";     value: evt ? evt.errorText || "" : ""; isError: true; multiline: true }
        }
    }

    component FieldRow: RowLayout {
        property string name: ""
        property string value: ""
        property bool   mono: false
        property bool   multiline: false
        property bool   isError: false
        // 0 shows the full value. The cut prefers the last space before the
        // limit so a hex byte pair is never split.
        property int    truncateAt: 0

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
            text: {
                if (truncateAt <= 0 || value.length <= truncateAt) return value
                let cut = value.lastIndexOf(" ", truncateAt)
                if (cut < truncateAt / 2) cut = truncateAt
                return value.substring(0, cut) + " …"
            }
            font.family: mono ? root.monoFont : Theme.typography.publicSans
            color: isError ? Theme.palette.error : Theme.palette.text
            // Hex/mono values have no word boundaries worth keeping; error
            // prose reads better broken at spaces.
            wrapMode: !multiline ? TextEdit.NoWrap
                                 : mono ? TextEdit.WrapAnywhere : TextEdit.Wrap
            Layout.fillWidth: true
        }
    }

    // Read-only TextEdit styled like LogosText, with mouse/keyboard selection
    // so developers can copy hashes, topics, peer IDs, etc. straight out of
    // the event log.
    // One RLN figure: its name above the value, with the call that produced it
    // on the info chip.
    component RlnStat: ColumnLayout {
        id: stat

        property string label: ""
        property string value: ""
        property string tip: ""
        property color  highlight: Theme.palette.text

        spacing: Theme.spacing.tiny
        Layout.fillWidth: true
        Layout.minimumWidth: 150

        RowLayout {
            spacing: Theme.spacing.tiny
            LogosText {
                text: stat.label
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            InfoChip { tip: stat.tip }
            Item { Layout.fillWidth: true }
        }
        LogosText {
            text: stat.value
            font.family: root.monoFont
            font.pixelSize: Theme.typography.primaryText
            font.weight: Theme.typography.weightBold
            color: stat.highlight
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

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

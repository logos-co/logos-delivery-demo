import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property var backend: logos.module("logos_delivery_demo")

    // QML-side state — single source of truth for the UI.
    // The backend forwards delivery_module events into this model.
    property var topics: ({})         // { topic: [ {direction, text, hash, requestId, ts, propagated, error} ] }
    property var topicList: []        // ordered list of subscribed topics
    property string selectedTopic: ""
    property string nodeStatus: backend ? backend.connectionStatus : "no backend"
    property bool nodeReady: backend ? backend.nodeReady : false
    property string lastError: backend ? backend.lastError : ""

    Connections {
        target: backend
        ignoreUnknownSignals: true

        function onMessageReceived(topic, payloadBase64, messageHash, timestamp) {
            root.appendMessage(topic, {
                direction: "in",
                text: Qt.atob(payloadBase64),
                hash: messageHash,
                ts: timestamp
            })
        }

        function onMessageSentNotif(requestId, messageHash) {
            root.updateOutgoing(requestId, { hash: messageHash, sent: true })
        }

        function onMessagePropagatedNotif(requestId, messageHash) {
            root.updateOutgoing(requestId, { hash: messageHash, propagated: true })
        }

        function onMessageErrorNotif(requestId, errorText) {
            root.updateOutgoing(requestId, { error: errorText })
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
        // Walk all topics looking for an entry with this requestId.
        const next = Object.assign({}, root.topics)
        for (const t in next) {
            for (const m of next[t]) {
                if (m.requestId === requestId) {
                    Object.assign(m, patch)
                }
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
                if (err && err.length > 0) {
                    root.lastError = "subscribe failed: " + err
                    return
                }
                root.topicList = root.topicList.concat([trimmed])
                const copy = Object.assign({}, root.topics)
                copy[trimmed] = []
                root.topics = copy
                root.selectedTopic = trimmed
                messageView.model = copy[trimmed]
                topicInput.text = ""
            },
            function(err) { root.lastError = String(err) }
        )
    }

    function removeTopic(topic) {
        if (!topic) return
        logos.watch(backend.unsubscribe(topic),
            function(err) {
                if (err && err.length > 0) {
                    root.lastError = "unsubscribe failed: " + err
                    return
                }
                root.topicList = root.topicList.filter(function(t) { return t !== topic })
                const copy = Object.assign({}, root.topics)
                delete copy[topic]
                root.topics = copy
                if (root.selectedTopic === topic) {
                    root.selectedTopic = root.topicList.length > 0 ? root.topicList[0] : ""
                    messageView.model = root.selectedTopic ? (copy[root.selectedTopic] || []) : []
                }
            },
            function(err) { root.lastError = String(err) }
        )
    }

    function sendMessage(topic, text) {
        if (!topic || !text) return
        logos.watch(backend.sendMessage(topic, text),
            function(requestId) {
                if (!requestId || requestId.length === 0) return  // setLastError on backend already populated
                root.appendMessage(topic, {
                    direction: "out",
                    text: text,
                    requestId: requestId,
                    sent: false,
                    propagated: false,
                    error: "",
                    ts: ""
                })
                sendInput.text = ""
            },
            function(err) { root.lastError = String(err) }
        )
    }

    // ─── Layout ────────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header / health
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "#1f1f2a"
            radius: 8

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    text: "Logos Delivery demo"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.nodeReady ? "#56d364" : "#f0a623"
                }

                Text {
                    text: "node: " + root.nodeStatus
                    color: "#c0c0c0"
                    font.pixelSize: 13
                }

                Button {
                    text: "?"
                    implicitWidth: 28
                    ToolTip.visible: hovered
                    ToolTip.delay: 200
                    ToolTip.text: "On load, the backend calls:\n  delivery_module.createNode({preset:'logos.dev', mode:'Core'})\n  delivery_module.start()\nand listens for connectionStateChanged events."
                }
            }
        }

        // Body
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // ── Left: topics
            Rectangle {
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                color: "#181821"
                radius: 8

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Text { text: "Content topics"; color: "#ffffff"; font.bold: true; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "?"
                            implicitWidth: 24
                            ToolTip.visible: hovered
                            ToolTip.delay: 200
                            ToolTip.text: "Each subscription calls delivery_module.subscribe(topic). Removing it calls delivery_module.unsubscribe(topic). Both return LogosResult."
                        }
                    }

                    RowLayout {
                        TextField {
                            id: topicInput
                            placeholderText: "/myapp/1/chat/proto"
                            Layout.fillWidth: true
                            onAccepted: root.addTopic(text)
                        }
                        Button {
                            text: "+"
                            enabled: root.nodeReady
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
                            color: modelData === root.selectedTopic ? "#2d3242" : "transparent"
                            radius: 4

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Text {
                                    text: modelData
                                    color: "#e8e8e8"
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.selectedTopic = modelData
                                            messageView.model = root.topics[modelData] || []
                                        }
                                    }
                                }

                                Button {
                                    text: "×"
                                    implicitWidth: 24
                                    onClicked: root.removeTopic(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Right: messages + send
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#181821"
                radius: 8

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Text {
                            text: root.selectedTopic.length > 0 ? root.selectedTopic : "Select or add a topic"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 14
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Button {
                            text: "?"
                            implicitWidth: 24
                            ToolTip.visible: hovered
                            ToolTip.delay: 200
                            ToolTip.text: "Incoming messages are delivered via the messageReceived event on delivery_module. Payloads arrive base64-encoded; the demo decodes them with Qt.atob()."
                        }
                    }

                    ListView {
                        id: messageView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: []

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: msgCol.implicitHeight + 12
                            radius: 6
                            color: modelData.direction === "out" ? "#1d3559" : "#262633"

                            ColumnLayout {
                                id: msgCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 6
                                spacing: 2

                                Text {
                                    text: modelData.text
                                    color: "#e8e8e8"
                                    font.pixelSize: 13
                                    wrapMode: Text.WrapAnywhere
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: modelData.direction === "out"
                                    text: {
                                        if (modelData.error)        return "✕ " + modelData.error
                                        if (modelData.propagated)   return "✓✓ propagated  " + (modelData.hash || "")
                                        if (modelData.sent)         return "✓  sent  " + (modelData.hash || "")
                                        return "… awaiting confirmation"
                                    }
                                    color: modelData.error ? "#f85149" : "#8b949e"
                                    font.pixelSize: 11
                                }

                                Text {
                                    visible: modelData.direction === "in"
                                    text: "hash: " + (modelData.hash || "")
                                    color: "#8b949e"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    RowLayout {
                        TextField {
                            id: sendInput
                            placeholderText: root.selectedTopic.length > 0 ? "Message to " + root.selectedTopic : "Pick a topic first"
                            Layout.fillWidth: true
                            enabled: root.nodeReady && root.selectedTopic.length > 0
                            onAccepted: root.sendMessage(root.selectedTopic, text)
                        }
                        Button {
                            text: "Send"
                            enabled: root.nodeReady && root.selectedTopic.length > 0 && sendInput.text.length > 0
                            onClicked: root.sendMessage(root.selectedTopic, sendInput.text)
                        }
                        Button {
                            text: "?"
                            implicitWidth: 24
                            ToolTip.visible: hovered
                            ToolTip.delay: 200
                            ToolTip.text: "Send calls delivery_module.send(topic, text). LogosResult.getString() returns a request ID; messageSent then messagePropagated events arrive asynchronously for that request ID."
                        }
                    }

                    Rectangle {
                        visible: root.lastError.length > 0
                        Layout.fillWidth: true
                        height: 32
                        radius: 4
                        color: "#3d1a1a"
                        Text {
                            anchors.centerIn: parent
                            text: root.lastError
                            color: "#f85149"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}

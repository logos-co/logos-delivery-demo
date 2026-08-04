#include "logos_delivery_demo_plugin.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_types.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>

LogosDeliveryDemoPlugin::LogosDeliveryDemoPlugin(QObject* parent)
    : LogosDeliveryDemoSimpleSource(parent)
{
}

LogosDeliveryDemoPlugin::~LogosDeliveryDemoPlugin()
{
    delete m_logos;
}

void LogosDeliveryDemoPlugin::initLogos(LogosAPI* api)
{
    if (m_logos) return;
    m_logosAPI = api;
    m_logos = new LogosModules(api);

    setBackend(this);

    wireEvents();

    // The node is no longer bootstrapped automatically — the UI drives it by
    // calling createNode(preset, mode), so the demo can be exercised against
    // different fleets (logos.dev / logos.test) and node modes (Core / Edge).
    //
    // delivery_module and its node are a singleton per Logos Core instance, so
    // the node may equally be created by another module (e.g. chat_module) —
    // possibly before this module loaded. Hence the read here, not just on the
    // nodeStarted event: node state is read from the module, never inferred
    // from who called createNode.
    readNodeInfo();
}

void LogosDeliveryDemoPlugin::wireEvents()
{
    m_logos->delivery_module.on("connectionStateChanged", [this](const QVariantList& data) {
        if (data.size() < 2) return;
        setConnectionStatus(data.at(0).toString());
        emit connectionStateChangedNotif(data.at(0).toString(), data.at(1).toLongLong());
    });

    // The node's lifecycle events. They fire regardless of which module drove
    // the call, so on a shared node these are also how the demo sees another
    // module's start / stop.
    m_logos->delivery_module.on("nodeStarted", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit nodeStartedNotif(data.at(0).toBool(), data.at(1).toString(), data.at(2).toLongLong());
        // Queued, not called inline: event callbacks arrive on delivery_module's
        // dispatch thread, and the SDK invokes module methods with
        // Qt::DirectConnection — so a getNodeInfo issued from here would run on
        // that thread, where its completion callback can't be served, and would
        // write PROPs off the source's thread. Hop back to ours first.
        QMetaObject::invokeMethod(this, [this] { readNodeInfo(); }, Qt::QueuedConnection);
    });

    m_logos->delivery_module.on("nodeStopped", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit nodeStoppedNotif(data.at(0).toBool(), data.at(1).toString(), data.at(2).toLongLong());
        QMetaObject::invokeMethod(this, [this] { clearNodeInfo(); }, Qt::QueuedConnection);
    });

    m_logos->delivery_module.on("messageReceived", [this](const QVariantList& data) {
        if (data.size() < 4) return;
        // data[2] is the message payload — arbitrary bytes, not text. Surface it
        // as a space-separated hex string so the UI shows it as bytes.
        const QByteArray payload = data.at(2).toByteArray();

        // data[3] is the timestamp as a qint64 unix timestamp (nanoseconds since
        // epoch). Since logos-delivery-module #29 every event reports its
        // timestamp this way (messageReceived carries the received message's own
        // timestamp; the others carry a local wall-clock time), so the slot is a
        // qint64 across all events now.
        emit messageReceived(
            data.at(1).toString(),                       // contentTopic
            QString::fromLatin1(payload.toHex(' ')),     // payload (hex bytes)
            data.at(0).toString(),                       // messageHash
            data.at(3).toLongLong());                    // timestamp (qint64, ns since epoch)
    });

    m_logos->delivery_module.on("messageSent", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit messageSentNotif(data.at(0).toString(), data.at(1).toString(), data.at(2).toLongLong());
    });

    m_logos->delivery_module.on("messagePropagated", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit messagePropagatedNotif(data.at(0).toString(), data.at(1).toString(), data.at(2).toLongLong());
    });

    m_logos->delivery_module.on("messageError", [this](const QVariantList& data) {
        if (data.size() < 4) return;
        emit messageErrorNotif(data.at(0).toString(), data.at(1).toString(), data.at(2).toString(), data.at(3).toLongLong());
    });

    m_logos->delivery_module.on("channelMessageReceived", [this](const QVariantList& data) {
        if (data.size() < 4) return;
        const QByteArray payload = data.at(2).toByteArray();
        emit channelMessageReceived(
            data.at(0).toString(),                       // channelId
            data.at(1).toString(),                       // senderId
            QString::fromLatin1(payload.toHex(' ')),     // payload (hex bytes)
            data.at(3).toLongLong());                    // timestamp (qint64, ns since epoch)
    });

    m_logos->delivery_module.on("channelMessageSent", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit channelMessageSentNotif(data.at(0).toString(), data.at(1).toString(), data.at(2).toLongLong());
    });

    m_logos->delivery_module.on("channelMessageError", [this](const QVariantList& data) {
        if (data.size() < 4) return;
        emit channelMessageErrorNotif(data.at(0).toString(), data.at(1).toString(), data.at(2).toString(), data.at(3).toLongLong());
    });
}

QString LogosDeliveryDemoPlugin::createNode(QString preset, QString mode)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    if (nodeReady()) return QStringLiteral("Node already created");

    // No port config: the layered shape gets ephemeral p2p ports (logos-delivery
    // defaults them to 0), so two demo instances on one machine don't collide.
    // Keep bare kernel fields (logLevel, entry-layer, ports) out of the top
    // level — one bare field switches parsing to the legacy flat path, whose
    // fixed port defaults do collide. Preset (logos.dev / logos.test) and mode
    // (Core / Edge) come from the UI.
    QJsonObject cfg{
        {"mode", mode},
        {"preset", preset},
        {"messagingOverrides", QJsonObject{{"logLevel", "INFO"}}},
    };
    const QString cfgJson = QString::fromUtf8(QJsonDocument(cfg).toJson(QJsonDocument::Compact));
    qInfo() << "logos_delivery_demo: createNode" << cfgJson;

    LogosResult create = m_logos->delivery_module.createNode(cfgJson);
    if (!create.success) {
        setLastError(QStringLiteral("createNode failed: %1").arg(create.getError()));
        return create.getError();
    }

    qInfo() << "logos_delivery_demo: createNode succeeded, starting node...";

    LogosResult started = m_logos->delivery_module.start();
    if (!started.success) {
        setLastError(QStringLiteral("start failed: %1").arg(started.getError()));
        return started.getError();
    }

    qInfo() << "logos_delivery_demo: Node started successfully";

    return QString();
}

// Read the node's fixed attributes. Both are constant for the life of the node
// — the peer id derives from the node key at construction, the version is a
// build-time constant of liblogosdelivery — so they are read once per node
// rather than polled: at init (the node may already exist, created by another
// module) and on nodeStarted.
void LogosDeliveryDemoPlugin::readNodeInfo()
{
    if (!m_logos) return;

    // Doubles as the node-exists probe: getNodeInfo fails with "Context not
    // initialized" until some module has called createNode.
    LogosResult peer = m_logos->delivery_module.getNodeInfo(QStringLiteral("MyPeerId"));
    if (!peer.success) {
        clearNodeInfo();
        return;
    }
    setPeerId(peer.getString());

    // logos-delivery (liblogosdelivery) version. Exposed as the "Version"
    // getNodeInfo attribute — the same call delivery_module's own version()
    // wraps.
    LogosResult version = m_logos->delivery_module.getNodeInfo(QStringLiteral("Version"));
    if (version.success) {
        setDeliveryVersion(version.getString());
    }

    setNodeReady(true);
}

void LogosDeliveryDemoPlugin::clearNodeInfo()
{
    setNodeReady(false);
    setPeerId(QString());
    setDeliveryVersion(QString());
}

QString LogosDeliveryDemoPlugin::subscribe(QString topic)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.subscribe(topic);
    if (!r.success) {
        setLastError(QStringLiteral("subscribe(%1) failed: %2").arg(topic, r.getError()));
        return r.getError();
    }
    return QString();
}

QString LogosDeliveryDemoPlugin::unsubscribe(QString topic)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.unsubscribe(topic);
    if (!r.success) {
        setLastError(QStringLiteral("unsubscribe(%1) failed: %2").arg(topic, r.getError()));
        return r.getError();
    }
    return QString();
}

QString LogosDeliveryDemoPlugin::sendMessage(QString topic, QString payloadHex)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    // The payload is arbitrary bytes; the UI provides them as a hex string.
    // send()'s payload arg is a QVariant carrying a QByteArray — pass the raw
    // bytes so they cross unchanged (a QString would be re-encoded as UTF-8).
    const QByteArray payload = QByteArray::fromHex(payloadHex.toLatin1());
    LogosResult r = m_logos->delivery_module.send(topic, payload);
    if (!r.success) {
        setLastError(QStringLiteral("send(%1) failed: %2").arg(topic, r.getError()));
        return QString();
    }
    return r.getString();  // request ID
}

QString LogosDeliveryDemoPlugin::channelCreate(QString channelId, QString contentTopic, QString senderId)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.channelCreate(channelId, contentTopic, senderId);
    if (!r.success) {
        setLastError(QStringLiteral("channelCreate(%1) failed: %2").arg(channelId, r.getError()));
        return r.getError();
    }
    return QString();
}

QString LogosDeliveryDemoPlugin::channelExists(QString channelId)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.channelExists(channelId);
    if (!r.success) {
        setLastError(QStringLiteral("channelExists(%1) failed: %2").arg(channelId, r.getError()));
        return QString();
    }
    return r.getString();  // "true" / "false", verbatim from the FFI
}

QString LogosDeliveryDemoPlugin::channelSend(QString channelId, QString payloadHex)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    // Same convention as sendMessage().
    const QByteArray payload = QByteArray::fromHex(payloadHex.toLatin1());
    LogosResult r = m_logos->delivery_module.channelSend(channelId, payload);
    if (!r.success) {
        setLastError(QStringLiteral("channelSend(%1) failed: %2").arg(channelId, r.getError()));
        return QString();
    }
    return r.getString();  // request ID
}

QString LogosDeliveryDemoPlugin::channelClose(QString channelId)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.channelClose(channelId);
    if (!r.success) {
        setLastError(QStringLiteral("channelClose(%1) failed: %2").arg(channelId, r.getError()));
        return r.getError();
    }
    return QString();
}

#include "logos_delivery_demo_plugin.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_types.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

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
}

void LogosDeliveryDemoPlugin::wireEvents()
{
    m_logos->delivery_module.on("connectionStateChanged", [this](const QVariantList& data) {
        if (data.isEmpty()) return;
        setConnectionStatus(data.at(0).toString());
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
}

QString LogosDeliveryDemoPlugin::createNode(QString preset, QString mode)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    if (nodeReady()) return QStringLiteral("Node already created");

    // No port config: logos-delivery-module defaults unspecified ports to 0, so
    // the OS assigns free ports and two demo instances on one machine don't
    // collide — no port-shift workaround needed. Preset (logos.dev / logos.test)
    // and mode (Core / Edge) come from the UI.
    QJsonObject cfg{
        {"logLevel", "INFO"},
        {"mode", mode},
        {"preset", preset}
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

    setNodeReady(true);

    // logos-delivery (liblogosdelivery) version. Exposed as the "Version"
    // getNodeInfo attribute — the same call delivery_module's own version()
    // wraps. It's fixed for the life of the node, so fetch it once here
    // rather than in the 3s poll below.
    LogosResult version = m_logos->delivery_module.getNodeInfo(QStringLiteral("Version"));
    if (version.success) {
        setDeliveryVersion(version.getString());
    }

    // Poll the node's peer id every 3s — the module only exposes it via
    // getNodeInfo, so we surface it to QML as an auto-synced PROP.
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(3000);
    QObject::connect(m_pollTimer, &QTimer::timeout, this, &LogosDeliveryDemoPlugin::refreshNodeInfo);
    refreshNodeInfo();
    m_pollTimer->start();

    return QString();
}

void LogosDeliveryDemoPlugin::refreshNodeInfo()
{
    if (!m_logos) return;

    LogosResult peer = m_logos->delivery_module.getNodeInfo(QStringLiteral("MyPeerId"));
    if (peer.success) {
        setPeerId(peer.getString());
    }
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

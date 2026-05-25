#include "logos_delivery_demo_plugin.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_types.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
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

    // Defer the node bootstrap to the next event-loop turn. The ui-host runs
    // initLogos() on its main thread and only prints its READY marker to the
    // host *after* this returns; createNode()/start() are synchronous and
    // network-bound (several seconds), so running them inline would delay READY
    // past the host's readiness timeout and the module would be reported as
    // "Failed to load UI plugin". A queued singleShot fires once the ui-host
    // has signalled READY and entered its event loop.
    QTimer::singleShot(0, this, [this]() { bootstrapNode(); });
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

void LogosDeliveryDemoPlugin::bootstrapNode()
{
    // No port config: logos-delivery-module defaults unspecified ports to 0, so
    // the OS assigns free ports and two demo instances on one machine don't
    // collide — no port-shift workaround needed.
    QJsonObject cfg{
        {"logLevel", "INFO"},
        {"mode", "Core"},
        {"preset", "logos.dev"}
    };
    const QString cfgJson = QString::fromUtf8(QJsonDocument(cfg).toJson(QJsonDocument::Compact));
    qInfo() << "logos_delivery_demo: createNode" << cfgJson;

    LogosResult create = m_logos->delivery_module.createNode(cfgJson);
    if (!create.success) {
        setLastError(QStringLiteral("createNode failed: %1").arg(create.getError()));
        return;
    }

    qInfo() << "logos_delivery_demo: createNode succeeded, starting node...";

    LogosResult started = m_logos->delivery_module.start();
    if (!started.success) {
        setLastError(QStringLiteral("start failed: %1").arg(started.getError()));
        return;
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

    // Poll node info (peer id, peer count) every 3s — the module only exposes
    // them via getNodeInfo, so we surface them to QML as auto-synced PROPs.
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(3000);
    QObject::connect(m_pollTimer, &QTimer::timeout, this, &LogosDeliveryDemoPlugin::refreshNodeInfo);
    refreshNodeInfo();
    m_pollTimer->start();
}

void LogosDeliveryDemoPlugin::refreshNodeInfo()
{
    if (!m_logos) return;

    LogosResult peer = m_logos->delivery_module.getNodeInfo(QStringLiteral("MyPeerId"));
    if (peer.success) {
        setPeerId(peer.getString());
    }

    LogosResult metrics = m_logos->delivery_module.getNodeInfo(QStringLiteral("Metrics"));
    if (metrics.success) {
        // The Metrics endpoint returns Prometheus text. Grep `libp2p_peers <n>`
        // — it's the only widely-supported peer-count gauge in libp2p.
        const QString body = metrics.getString();
        static const QRegularExpression rx(QStringLiteral("^libp2p_peers\\s+(\\d+)"),
                                            QRegularExpression::MultilineOption);
        const QRegularExpressionMatch m = rx.match(body);
        if (m.hasMatch()) {
            setPeerCount(m.captured(1).toInt());
        }
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

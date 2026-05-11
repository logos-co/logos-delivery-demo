#include "logos_delivery_demo_plugin.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_types.h"
#include "logos_instance.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>

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
    bootstrapNode();
}

void LogosDeliveryDemoPlugin::wireEvents()
{
    m_logos->delivery_module.on("connectionStateChanged", [this](const QVariantList& data) {
        if (data.isEmpty()) return;
        setConnectionStatus(data.at(0).toString());
    });

    m_logos->delivery_module.on("messageReceived", [this](const QVariantList& data) {
        if (data.size() < 4) return;
        emit messageReceived(
            data.at(1).toString(),  // contentTopic
            data.at(2).toString(),  // payload (base64)
            data.at(0).toString(),  // messageHash
            data.at(3).toString()); // timestamp
    });

    m_logos->delivery_module.on("messageSent", [this](const QVariantList& data) {
        if (data.size() < 2) return;
        emit messageSentNotif(data.at(0).toString(), data.at(1).toString());
    });

    m_logos->delivery_module.on("messagePropagated", [this](const QVariantList& data) {
        if (data.size() < 2) return;
        emit messagePropagatedNotif(data.at(0).toString(), data.at(1).toString());
    });

    m_logos->delivery_module.on("messageError", [this](const QVariantList& data) {
        if (data.size() < 3) return;
        emit messageErrorNotif(data.at(0).toString(), data.at(2).toString());
    });
}

void LogosDeliveryDemoPlugin::bootstrapNode()
{
    // Derive a unique port window per Logos instance so two demo instances
    // on one machine don't collide on tcp/rest/metrics/discv5/websocket ports.
    // LogosInstance::id() is provisioned by logos_core_start() / logoscore
    // and inherited via LOGOS_INSTANCE_ID; child processes see the same id.
    const QString instanceId = LogosInstance::id();
    bool ok = false;
    const uint hex = instanceId.left(4).toUInt(&ok, 16);
    const int portsShift = static_cast<int>(
        100 + ((ok ? hex : QRandomGenerator::global()->generate()) % 4500));

    QJsonObject cfg{
        {"logLevel", "INFO"},
        {"mode", "Core"},
        {"preset", "logos.dev"},
        {"portsShift", portsShift}
    };
    const QString cfgJson = QString::fromUtf8(QJsonDocument(cfg).toJson(QJsonDocument::Compact));
    qInfo() << "logos_delivery_demo: createNode portsShift=" << portsShift
            << "instanceId=" << instanceId;

    LogosResult create = m_logos->delivery_module.createNode(cfgJson);
    if (!create.success) {
        setLastError(QStringLiteral("createNode failed: %1").arg(create.getError()));
        return;
    }

    LogosResult started = m_logos->delivery_module.start();
    if (!started.success) {
        setLastError(QStringLiteral("start failed: %1").arg(started.getError()));
        return;
    }

    setNodeReady(true);
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

QString LogosDeliveryDemoPlugin::sendMessage(QString topic, QString text)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    LogosResult r = m_logos->delivery_module.send(topic, text);
    if (!r.success) {
        setLastError(QStringLiteral("send(%1) failed: %2").arg(topic, r.getError()));
        return QString();
    }
    return r.getString();  // request ID
}

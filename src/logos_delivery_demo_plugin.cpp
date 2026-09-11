#include "logos_delivery_demo_plugin.h"
#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_types.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMetaObject>

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

    // The delivery library asks for one proof per outbound message and one
    // validation per inbound one, so these are the node's live RLN traffic.
    // They keep firing even though the in-process bridge answers them.
    m_logos->delivery_module.on("dispatchRlnGenerateProofRequestEvent", [this](const QVariantList& data) {
        if (data.size() < 6) return;
        setRlnProofs(rlnProofs() + 1);
        emit rlnProofRequested(data.at(3).toString(), data.at(4).toLongLong(), data.at(5).toLongLong());
        pollRlnQuota();
    });
    m_logos->delivery_module.on("dispatchRlnValidateProofRequestEvent", [this](const QVariantList& data) {
        if (data.size() < 7) return;
        setRlnValidations(rlnValidations() + 1);
        emit rlnValidationRequested(data.at(3).toString(), data.at(4).toLongLong(), data.at(6).toLongLong());
    });

    // A push from the RLN module's confirmation poller. get_membership_state
    // stays the authority, so this only wakes an immediate re-read.
    m_logos->liblogos_rln_module.onMembership_state_changed(
        [this](const QString& registryId, const QString& rlnIdentifier,
               const QString& membershipHash, const QString& state, const QString& previous) {
            if (registryId != m_rlnRegistryId) return;
            Q_UNUSED(rlnIdentifier);
            QMetaObject::invokeMethod(this, [this, membershipHash, state, previous]() {
                emit rlnMembershipTransition(membershipHash, state, previous);
                pollRlnMembership();
            }, Qt::QueuedConnection);
        });
}

// liblogos_rln_module answers `result` methods with the value as a QVariantMap
// and `tstr` methods with a JSON string, so both shapes reach this.
static QJsonObject rlnObject(const QVariant& value)
{
    if (value.canConvert<QVariantMap>() && value.typeId() != QMetaType::QString) {
        return QJsonObject::fromVariantMap(value.toMap());
    }
    return QJsonDocument::fromJson(value.toString().toUtf8()).object();
}

// The module reports a failed `tstr` call in band, as {"error":{…}}.
static QString rlnInBandError(const QJsonObject& obj)
{
    const QJsonObject err = obj.value(QStringLiteral("error")).toObject();
    if (err.isEmpty()) return QString();
    return QStringLiteral("%1: %2")
        .arg(err.value(QStringLiteral("kind")).toString(),
             err.value(QStringLiteral("message")).toString());
}

void LogosDeliveryDemoPlugin::startRlnPolling()
{
    if (m_rlnQuotaTimer) return;

    // The quota is a local read, so it can be cheap and frequent; the
    // membership state costs a registry read, and matches the 10s the RLN
    // membership UI polls at.
    m_rlnQuotaTimer = new QTimer(this);
    m_rlnQuotaTimer->setInterval(2000);
    connect(m_rlnQuotaTimer, &QTimer::timeout, this, &LogosDeliveryDemoPlugin::pollRlnQuota);
    m_rlnQuotaTimer->start();

    m_rlnMembershipTimer = new QTimer(this);
    m_rlnMembershipTimer->setInterval(10000);
    connect(m_rlnMembershipTimer, &QTimer::timeout, this, &LogosDeliveryDemoPlugin::pollRlnMembership);
    m_rlnMembershipTimer->start();

    pollRlnQuota();
    pollRlnMembership();
}

void LogosDeliveryDemoPlugin::pollRlnQuota()
{
    if (!m_logos || m_rlnRegistryId.isEmpty()) return;

    // The same clock reading a send would stamp on its message: the epoch is
    // derived from the timestamp, not from the module's own clock.
    const QString now = QString::number(QDateTime::currentSecsSinceEpoch());
    m_logos->liblogos_rln_module.get_epoch_quotaAsync(
        m_rlnRegistryId, m_rlnIdentifier, now, [this](LogosResult result) {
            QMetaObject::invokeMethod(this, [this, result]() {
                if (!result.success) {
                    setRlnStatus(result.getError());
                    setRlnRemaining(-1);
                    return;
                }
                const QJsonObject obj = rlnObject(result.value);
                setRlnEpochIndex(QString::number(
                    static_cast<qint64>(obj.value(QStringLiteral("epoch_index")).toDouble())));
                setRlnRateLimit(obj.value(QStringLiteral("rate_limit")).toInt());
                setRlnRemaining(obj.value(QStringLiteral("remaining")).toInt());
                setRlnStatus(QString());
            }, Qt::QueuedConnection);
        });
}

void LogosDeliveryDemoPlugin::pollRlnMembership()
{
    if (!m_logos || m_rlnRegistryId.isEmpty()) return;

    m_logos->liblogos_rln_module.get_membership_stateAsync(
        m_rlnRegistryId, m_rlnIdentifier, [this](QString reply) {
            QMetaObject::invokeMethod(this, [this, reply]() {
                const QJsonObject obj = QJsonDocument::fromJson(reply.toUtf8()).object();
                const QString err = rlnInBandError(obj);
                if (!err.isEmpty()) {
                    setRlnStatus(err);
                    setRlnMembershipState(QStringLiteral("unknown"));
                    return;
                }
                setRlnMembershipState(obj.value(QStringLiteral("state")).toString());
                setRlnMembershipHash(obj.value(QStringLiteral("membership_hash")).toString());
            }, Qt::QueuedConnection);
        });
}

QString LogosDeliveryDemoPlugin::configureRln(QString registryId, QString rlnIdentifier,
                                             QString epochSizeSec)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    if (nodeReady()) return QStringLiteral("Node already created");

    QJsonObject cfg{
        {"registry-id", registryId.trimmed()},
        {"rln-identifier", rlnIdentifier.trimmed()},
    };

    // Not optional: liblogos_rln_module.start() refuses a config without it,
    // and delivery_module only forwards the key when it is set.
    bool epochOk = false;
    const qint64 epoch = epochSizeSec.trimmed().toLongLong(&epochOk);
    if (!epochOk || epoch <= 0) return QStringLiteral("epochSizeSec must be a positive integer");
    cfg.insert(QStringLiteral("epoch-size-sec"), epoch);

    const QString cfgJson = QString::fromUtf8(QJsonDocument(cfg).toJson(QJsonDocument::Compact));
    qInfo() << "logos_delivery_demo: configureRln" << cfgJson;

    LogosResult configured = m_logos->delivery_module.configureRln(cfgJson);
    if (!configured.success) {
        setLastError(QStringLiteral("configureRln failed: %1").arg(configured.getError()));
        return configured.getError();
    }

    qInfo() << "logos_delivery_demo: configureRln succeeded";

    m_rlnRegistryId = registryId.trimmed();
    m_rlnIdentifier = rlnIdentifier.trimmed();
    setRlnEpochSizeSec(static_cast<int>(epoch));
    setRlnConfigured(true);
    startRlnPolling();

    return QString();
}

QString LogosDeliveryDemoPlugin::createNode(QString preset, QString mode, QString anonymityLevel)
{
    // No port config: the layered shape gets ephemeral p2p ports (logos-delivery
    // defaults them to 0), so two demo instances on one machine don't collide.
    // Keep bare kernel fields (logLevel, entry-layer, ports) out of the top
    // level — one bare field switches parsing to the legacy flat path, whose
    // fixed port defaults do collide. Preset (logos.dev / logos.test), mode
    // (Core / Edge) and anonymity level come from the UI.
    QJsonObject cfg{
        {"mode", mode},
        {"preset", preset},
        {"messagingOverrides", QJsonObject{
            {"logLevel", "INFO"},
            {"anonymityLevel", anonymityLevel},
        }},
    };

    return startNode(QString::fromUtf8(QJsonDocument(cfg).toJson(QJsonDocument::Compact)));
}

QString LogosDeliveryDemoPlugin::createNodeWithConfig(QString configJson)
{
    const QString cfgJson = configJson.trimmed();
    if (cfgJson.isEmpty()) return QStringLiteral("Config is empty");

    // Rejected here rather than at the FFI boundary, where a malformed config
    // surfaces as a parse error with no position.
    QJsonParseError parseError{};
    const QJsonDocument parsed = QJsonDocument::fromJson(cfgJson.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        return QStringLiteral("Config is not valid JSON: %1 (at offset %2)")
            .arg(parseError.errorString())
            .arg(parseError.offset);
    }
    if (!parsed.isObject()) return QStringLiteral("Config must be a JSON object");

    return startNode(cfgJson);
}

// Both entry points end here: logos-delivery owns the config grammar, so the
// JSON crosses the FFI boundary verbatim either way.
QString LogosDeliveryDemoPlugin::startNode(const QString& cfgJson)
{
    if (!m_logos) return QStringLiteral("Backend not initialised");
    if (nodeReady()) return QStringLiteral("Node already created");

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

// Read the node's fixed attributes. All three are constant for the life of the
// node — the peer id derives from the node key at construction, the listening
// multiaddresses are fixed once it binds, the version is a build-time constant
// of liblogosdelivery — so they are read once per node rather than polled: at
// init (the node may already exist, created by another module) and on
// nodeStarted.
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

    // Feeding one of these to another node's entry-node peers them locally.
    LogosResult addrs = m_logos->delivery_module.getNodeInfo(QStringLiteral("MyMultiaddresses"));
    if (addrs.success) {
        setMultiaddrs(addrs.getString());
    }

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
    setMultiaddrs(QString());
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

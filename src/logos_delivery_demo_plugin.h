#ifndef LOGOS_DELIVERY_DEMO_PLUGIN_H
#define LOGOS_DELIVERY_DEMO_PLUGIN_H

#include <QByteArray>
#include <QHash>
#include <QMutex>
#include <QString>
#include <QVariantList>
#include <QTimer>
#include "logos_delivery_demo_interface.h"
#include "LogosViewPluginBase.h"
#include "rep_logos_delivery_demo_source.h"

class LogosAPI;
class LogosModules;

class LogosDeliveryDemoPlugin : public LogosDeliveryDemoSimpleSource,
                                public LogosDeliveryDemoInterface,
                                public LogosDeliveryDemoViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID LogosDeliveryDemoInterface_iid FILE "metadata.json")
    Q_INTERFACES(LogosDeliveryDemoInterface PluginInterface)

public:
    explicit LogosDeliveryDemoPlugin(QObject* parent = nullptr);
    ~LogosDeliveryDemoPlugin() override;

    QString name()    const override { return "logos_delivery_demo"; }
    QString version() const override { return "0.1.0"; }

    Q_INVOKABLE void initLogos(LogosAPI* api);

    QString configureRln(QString registryId, QString rlnIdentifier, QString epochSizeSec) override;
    QString createNode(QString preset, QString mode, QString anonymityLevel) override;
    QString createNodeWithConfig(QString configJson) override;
    QString subscribe(QString topic) override;
    QString unsubscribe(QString topic) override;
    QString sendMessage(QString topic, QString payloadHex) override;
    QString channelCreate(QString channelId, QString contentTopic, QString senderId, QString keyHex) override;
    QString generateChannelKey() override;
    QString channelExists(QString channelId) override;
    QString channelSend(QString channelId, QString payloadHex) override;
    QString channelClose(QString channelId) override;

    // The cipher target delivery_module relays an encrypted channel's
    // encrypt/decrypt to. Registered per channel at channelCreate; the module
    // reaches them by name over the protocol, so they are Q_INVOKABLE rather
    // than part of the .rep view contract.
    //
    // Payloads cross base64-encoded; an empty answer fails the message, which
    // is what a key mismatch on decrypt looks like.
    //
    // Both run on whichever thread delivery_module dispatches on, not the
    // demo's, so they touch nothing but the key table (guarded) and must stay
    // free of calls back into delivery_module.
    Q_INVOKABLE QString channelEncrypt(QString channelId, QString payloadB64);
    Q_INVOKABLE QString channelDecrypt(QString channelId, QString payloadB64);

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    void wireEvents();
    QString startNode(const QString& cfgJson);
    void readNodeInfo();
    void clearNodeInfo();

    void startRlnPolling();
    void pollRlnQuota();
    void pollRlnMembership();

    LogosAPI* m_logosAPI = nullptr;
    LogosModules* m_logos = nullptr;

    QByteArray channelKey(const QString& channelId) const;
    QString encryptedChannelList() const;
    QString runCipher(const QString& channelId, const QString& payloadB64, bool encrypting);

    // Channel id -> key, written by channelCreate on the demo's thread and read
    // by the cipher slots on delivery_module's.
    mutable QMutex m_channelKeysLock;
    QHash<QString, QByteArray> m_channelKeys;

    QString m_rlnRegistryId;
    QString m_rlnIdentifier;
    QTimer* m_rlnQuotaTimer = nullptr;
    QTimer* m_rlnMembershipTimer = nullptr;
};

#endif // LOGOS_DELIVERY_DEMO_PLUGIN_H

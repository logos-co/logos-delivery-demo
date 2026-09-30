#ifndef DELIVERY_DEMO_PLUGIN_H
#define DELIVERY_DEMO_PLUGIN_H

#include <QString>
#include <QVariantList>
#include <QTimer>
#include "delivery_demo_interface.h"
#include "LogosViewPluginBase.h"
#include "rep_delivery_demo_source.h"

class LogosAPI;
class LogosModules;

class DeliveryDemoPlugin : public DeliveryDemoSimpleSource,
                                public DeliveryDemoInterface,
                                public DeliveryDemoViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID DeliveryDemoInterface_iid FILE "metadata.json")
    Q_INTERFACES(DeliveryDemoInterface)

public:
    explicit DeliveryDemoPlugin(QObject* parent = nullptr);
    ~DeliveryDemoPlugin() override;

    QString name()    const override { return "delivery_demo"; }
    QString version() const override { return "0.1.0"; }

    Q_INVOKABLE void initLogos(LogosAPI* api);

    QString createNode(QString preset, QString mode, QString anonymityLevel) override;
    QString createNodeWithConfig(QString configJson) override;
    QString subscribe(QString topic) override;
    QString unsubscribe(QString topic) override;
    QString sendMessage(QString topic, QString payloadHex) override;
    QString channelCreate(QString channelId, QString contentTopic, QString senderId) override;
    QString channelExists(QString channelId) override;
    QString channelSend(QString channelId, QString payloadHex) override;
    QString channelClose(QString channelId) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    void wireEvents();
    QString startNode(const QString& cfgJson);
    void readNodeInfo();
    void clearNodeInfo();
    void readConnectionStatus();

    void settleAdoptedNode();
    void readRlnState();
    void applyRlnState(const QString& state, const QString& message);
    void adoptRlnDeployment();
    void startRlnPolling();
    void pollRlnQuota();
    void pollRlnMembership();

    LogosAPI* m_logosAPI = nullptr;
    LogosModules* m_logos = nullptr;

    QString m_rlnRegistryId;
    QString m_rlnIdentifier;
    QTimer* m_rlnQuotaTimer = nullptr;
    QTimer* m_rlnMembershipTimer = nullptr;
    QTimer* m_adoptTimer = nullptr;
};

#endif // DELIVERY_DEMO_PLUGIN_H

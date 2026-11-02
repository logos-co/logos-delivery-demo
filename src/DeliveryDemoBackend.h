#ifndef DELIVERY_DEMO_BACKEND_H
#define DELIVERY_DEMO_BACKEND_H

#include <QString>
#include <QTimer>
#include "logos_ui_plugin_context.h"
#include "rep_delivery_demo_source.h"

// View backend for the delivery demo. Derives the repc SimpleSource (the
// contract QML's replica binds to) plus LogosUiPluginContext, which supplies
// onContextReady() and the typed modules() accessor to the dependencies
// declared in metadata.json. The Q_PLUGIN_METADATA/initLogos plumbing that
// used to live here is generated now (delivery_demo_ui_glue.*).
class DeliveryDemoBackend : public DeliveryDemoSimpleSource,
                            public LogosUiPluginContext
{
    Q_OBJECT

public:
    explicit DeliveryDemoBackend(QObject* parent = nullptr);
    ~DeliveryDemoBackend() override;

    // Fires once the generated plugin glue has wired modules(); the typed
    // dependency surface is live, so event subscriptions happen here.
    void onContextReady() override;

    QString createNode(QString preset, QString mode, QString anonymityLevel) override;
    QString createNodeWithConfig(QString configJson) override;
    QString subscribe(QString topic) override;
    QString unsubscribe(QString topic) override;
    QString sendMessage(QString topic, QString payloadHex) override;
    QString channelCreate(QString channelId, QString contentTopic, QString senderId) override;
    QString channelExists(QString channelId) override;
    QString channelSend(QString channelId, QString payloadHex) override;
    QString channelClose(QString channelId) override;

private:
    void wireEvents();
    QString startNode(const QString& cfgJson);
    void readNodeInfo();
    void clearNodeInfo();
    void readConnectionStatus();

    void readRlnState();
    void applyRlnState(const QString& state, const QString& message);
    void adoptRlnDeployment();
    void startRlnPolling();
    void pollRlnQuota();
    void pollRlnMembership();

    QString m_rlnRegistryId;
    QString m_rlnIdentifier;
    QTimer* m_rlnQuotaTimer = nullptr;
    QTimer* m_rlnMembershipTimer = nullptr;
};

#endif // DELIVERY_DEMO_BACKEND_H

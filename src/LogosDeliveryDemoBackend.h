#ifndef LOGOS_DELIVERY_DEMO_BACKEND_H
#define LOGOS_DELIVERY_DEMO_BACKEND_H

#include <QString>
#include <QVariantList>
#include "logos_ui_plugin_context.h"
#include "rep_logos_delivery_demo_source.h"

// View backend for the delivery demo. Derives the repc SimpleSource (the
// contract QML's replica binds to) plus LogosUiPluginContext, which supplies
// onContextReady() and the typed modules() accessor to the dependencies
// declared in metadata.json. The Q_PLUGIN_METADATA/initLogos plumbing that
// used to live here is generated now (logos_delivery_demo_ui_glue.*).
class LogosDeliveryDemoBackend : public LogosDeliveryDemoSimpleSource,
                                 public LogosUiPluginContext
{
    Q_OBJECT

public:
    explicit LogosDeliveryDemoBackend(QObject* parent = nullptr);
    ~LogosDeliveryDemoBackend() override;

    // Fires once the generated plugin glue has wired modules(); the typed
    // delivery_module surface is live, so event subscriptions happen here.
    void onContextReady() override;

    QString createNode(QString preset, QString mode) override;
    QString subscribe(QString topic) override;
    QString unsubscribe(QString topic) override;
    QString sendMessage(QString topic, QString payloadHex) override;
    QString channelCreate(QString channelId, QString contentTopic, QString senderId) override;
    QString channelExists(QString channelId) override;
    QString channelSend(QString channelId, QString payloadHex) override;
    QString channelClose(QString channelId) override;

private:
    void wireEvents();
    void readNodeInfo();
    void clearNodeInfo();

};

#endif // LOGOS_DELIVERY_DEMO_BACKEND_H

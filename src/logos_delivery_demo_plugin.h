#ifndef LOGOS_DELIVERY_DEMO_PLUGIN_H
#define LOGOS_DELIVERY_DEMO_PLUGIN_H

#include <QString>
#include <QVariantList>
#include "logos_delivery_demo_interface.h"
#include "LogosViewPluginBase.h"
#include "rep_logos_delivery_demo_source.h"

class LogosAPI;
class LogosModules;
class QTimer;

class LogosDeliveryDemoPlugin : public LogosDeliveryDemoSimpleSource,
                                public LogosDeliveryDemoInterface,
                                public LogosDeliveryDemoViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID LogosDeliveryDemoInterface_iid FILE "metadata.json")
    Q_INTERFACES(LogosDeliveryDemoInterface)

public:
    explicit LogosDeliveryDemoPlugin(QObject* parent = nullptr);
    ~LogosDeliveryDemoPlugin() override;

    QString name()    const override { return "logos_delivery_demo"; }
    QString version() const override { return "0.1.0"; }

    Q_INVOKABLE void initLogos(LogosAPI* api);

    QString subscribe(QString topic) override;
    QString unsubscribe(QString topic) override;
    QString sendMessage(QString topic, QString text) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    void wireEvents();
    void bootstrapNode();
    void refreshNodeInfo();

    LogosAPI* m_logosAPI = nullptr;
    LogosModules* m_logos = nullptr;
    QTimer* m_pollTimer = nullptr;
};

#endif // LOGOS_DELIVERY_DEMO_PLUGIN_H

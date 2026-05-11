#ifndef LOGOS_DELIVERY_DEMO_INTERFACE_H
#define LOGOS_DELIVERY_DEMO_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

class LogosDeliveryDemoInterface : public PluginInterface
{
public:
    virtual ~LogosDeliveryDemoInterface() = default;
};

#define LogosDeliveryDemoInterface_iid "org.logos.LogosDeliveryDemoInterface"
Q_DECLARE_INTERFACE(LogosDeliveryDemoInterface, LogosDeliveryDemoInterface_iid)

#endif // LOGOS_DELIVERY_DEMO_INTERFACE_H

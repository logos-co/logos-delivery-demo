#ifndef DELIVERY_DEMO_INTERFACE_H
#define DELIVERY_DEMO_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

class DeliveryDemoInterface : public PluginInterface
{
public:
    virtual ~DeliveryDemoInterface() = default;
};

#define DeliveryDemoInterface_iid "org.logos.DeliveryDemoInterface"
Q_DECLARE_INTERFACE(DeliveryDemoInterface, DeliveryDemoInterface_iid)

#endif // DELIVERY_DEMO_INTERFACE_H

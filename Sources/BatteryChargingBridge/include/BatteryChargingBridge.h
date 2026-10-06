#ifndef GLANCE_BATTERY_CHARGING_H
#define GLANCE_BATTERY_CHARGING_H
#include <stdbool.h>
// -1 unavailable, 0 not paused, 1 paused, 2 paused with a permitted override.
int GlanceReadChargingHold(void);
// Temporarily resume this charging session. Does not disable optimization.
bool GlanceChargeToFullNow(void);
#endif

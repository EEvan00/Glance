#ifndef ST_DISPLAY_FEATURES_H
#define ST_DISPLAY_FEATURES_H
#include <stdbool.h>
// 0 appearance, 1 Night Shift, 2 True Tone. State -1 means unavailable.
int STDisplayFeatureState(int feature);
bool STSetDisplayFeature(int feature, bool enabled);
#endif

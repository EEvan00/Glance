#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "DisplayFeaturesBridge.h"

typedef struct { int hour, minute; } STTime;
typedef struct { STTime from, to; } STSchedule;
// Verified against getBlueLightStatus:'s local runtime encoding.
typedef struct { BOOL active, enabled, locationEnabled; int mode; STSchedule schedule; uint64_t disableFlags; BOOL reserved; } STBlueLightStatus;
@interface NSObject (STDisplayRuntime)
- (BOOL)supported;
- (BOOL)available;
- (BOOL)enabled;
- (BOOL)setEnabled:(BOOL)value;
- (BOOL)setActive:(BOOL)value;
- (BOOL)getBlueLightStatus:(STBlueLightStatus *)status;
@end
static BOOL (*getAppearance)(void);
static void (*setAppearance)(BOOL);
static void loadDisplayRuntime(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Retained for the process lifetime; no timers or notification subscriptions.
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (sky) { getAppearance = dlsym(sky, "SLSGetAppearanceThemeLegacy"); setAppearance = dlsym(sky, "SLSSetAppearanceThemeLegacy"); }
    });
}
static id client(int feature) {
    Class type = NSClassFromString(feature == 1 ? @"CBBlueLightClient" : @"CBTrueToneClient");
    return type ? [[type alloc] init] : nil;
}
int STDisplayFeatureState(int feature) { @autoreleasepool {
    loadDisplayRuntime();
    if (feature == 0) return getAppearance && setAppearance ? (getAppearance() ? 1 : 0) : -1;
    if (feature != 1 && feature != 2) return -1;
    id c = client(feature);
    if (![c respondsToSelector:@selector(supported)] || ![c supported]) return -1;
    if (feature == 1) {
        STBlueLightStatus status = {0};
        return [c respondsToSelector:@selector(getBlueLightStatus:)] && [c getBlueLightStatus:&status] && status.disableFlags == 0 ? (status.active ? 1 : 0) : -1;
    }
    return [c respondsToSelector:@selector(available)] && [c available] && [c respondsToSelector:@selector(enabled)] ? ([c enabled] ? 1 : 0) : -1;
} }
bool STSetDisplayFeature(int feature, bool enabled) { @autoreleasepool {
    if (STDisplayFeatureState(feature) < 0) return false;
    if (feature == 0) { setAppearance(enabled); return true; }
    id c = client(feature);
    SEL selector = feature == 1 ? @selector(setActive:) : @selector(setEnabled:);
    if (![c respondsToSelector:selector]) return false;
    return feature == 1 ? [c setActive:enabled] : [c setEnabled:enabled];
} }

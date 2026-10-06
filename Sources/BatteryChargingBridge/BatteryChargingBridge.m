#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "BatteryChargingBridge.h"

// Private PowerUI selectors, verified on macOS 15.7.3. Load dynamically so an
// absent framework or changed signature disables this optional capability.
@interface NSObject (GlanceSmartCharging)
- (id)initWithClientName:(NSString *)name;
- (BOOL)isOBCEngaged:(BOOL *)engaged chargeLimit:(NSUInteger *)limit
    chargingOverrideAllowed:(BOOL *)allowed withError:(NSError **)error;
- (BOOL)temporarilyEnableCharging:(NSError **)error;
@end

static BOOL matches(Class cls, SEL selector, const char *encoding) {
    Method method = class_getInstanceMethod(cls, selector);
    // BOOL is C++ bool on arm64, but signed char on Intel macOS.
    NSString *expected = [[NSString stringWithUTF8String:encoding]
        stringByReplacingOccurrencesOfString:@"B"
        withString:[NSString stringWithUTF8String:@encode(BOOL)]];
    return method && strcmp(method_getTypeEncoding(method), expected.UTF8String) == 0;
}

static id chargingClient(void) {
    static NSBundle *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"];
        [framework load];
    });
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    if (!matches(cls, @selector(initWithClientName:), "@24@0:8@16") ||
        !matches(cls, @selector(isOBCEngaged:chargeLimit:chargingOverrideAllowed:withError:),
                 "B48@0:8^B16^Q24^B32^@40")) return nil;
    return [[cls alloc] initWithClientName:@"Glance"];
}

static int readHold(id client) {
    if (!client) return -1;
    BOOL engaged = NO, allowed = NO;
    NSUInteger limit = 100;
    NSError *error = nil;
    BOOL ok = [client isOBCEngaged:&engaged chargeLimit:&limit
        chargingOverrideAllowed:&allowed withError:&error];
    if (!ok || error) return -1;
    // A configured charge limit alone does not prove charging is paused.
    BOOL canOverride = allowed && matches([client class],
        @selector(temporarilyEnableCharging:), "B24@0:8^@16");
    return engaged ? (canOverride ? 2 : 1) : 0;
}

int GlanceReadChargingHold(void) { @autoreleasepool {
    @try { return readHold(chargingClient()); }
    @catch (NSException *exception) { return -1; }
} }

bool GlanceChargeToFullNow(void) { @autoreleasepool {
    @try {
        id client = chargingClient();
        if (readHold(client) != 2 ||
            !matches([client class], @selector(temporarilyEnableCharging:), "B24@0:8^@16")) return false;
        NSError *error = nil;
        BOOL accepted = [client temporarilyEnableCharging:&error];
        return accepted && !error;
    } @catch (NSException *exception) { return false; }
} }

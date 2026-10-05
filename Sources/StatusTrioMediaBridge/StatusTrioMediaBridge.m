#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "StatusTrioMediaBridge.h"

// Runtime declarations keep private symbols out of the application's link table.
// This dylib is loaded only in the short-lived system Perl media process.
@interface NSObject (STMediaRuntime)
+ (id)localOrigin;
+ (id)defaultPlayer;
+ (id)localNowPlayingPlayerPath;
- (id)initWithOrigin:(id)origin client:(id)client player:(id)player;
- (id)initWithPlayerPath:(id)path;
- (id)initWithData:(NSData *)data;
- (NSData *)data;
- (NSString *)displayName;
- (NSString *)bundleIdentifier;
- (NSString *)parentApplicationBundleIdentifier;
- (id)client;
- (id)player;
- (NSString *)identifier;
- (int)processIdentifier;
- (void)requestNowPlayingInfoOnQueue:(dispatch_queue_t)queue completion:(void (^)(NSDictionary *, NSError *))completion;
- (void)requestPlaybackStateOnQueue:(dispatch_queue_t)queue completion:(void (^)(unsigned int, NSError *))completion;
- (void)requestSupportedCommandsOnQueue:(dispatch_queue_t)queue completion:(void (^)(NSArray *, NSError *))completion;
- (void)sendCommand:(unsigned int)command options:(NSDictionary *)options queue:(dispatch_queue_t)queue completion:(void (^)(id))completion;
- (unsigned int)command;
- (BOOL)isEnabled;
- (NSError *)error;
- (unsigned int)sendError;
@end

static void *mediaHandle;
static void (*getClients)(dispatch_queue_t, void (^)(NSArray *));
static void (*getPlayerForClient)(id, id, dispatch_queue_t, void (^)(id, NSError *));
static void (*resolvePlayerPath)(id, dispatch_queue_t, void (^)(id, NSError *));
static BOOL (*sendToPlayer)(unsigned int, NSDictionary *, id, unsigned int, dispatch_queue_t, void (^)(id));
static void (*registerNotifications)(dispatch_queue_t);
static dispatch_queue_t worker;
static BOOL querying;
static BOOL dirty;
static NSArray *lastOutput;
static dispatch_source_t queryDeadline;

static BOOL loadRuntime(void) {
    mediaHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!mediaHandle) return NO;
    getClients = dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingClients");
    getPlayerForClient = dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingPlayerForClient");
    resolvePlayerPath = dlsym(mediaHandle, "MRMediaRemoteNowPlayingResolvePlayerPath");
    sendToPlayer = dlsym(mediaHandle, "MRMediaRemoteSendCommandToPlayerWithResult");
    registerNotifications = dlsym(mediaHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    return getClients && getPlayerForClient && resolvePlayerPath && registerNotifications && NSClassFromString(@"MRNowPlayingRequest") && NSClassFromString(@"MRPlayerPath");
}

static double number(NSDictionary *info, NSString *suffix, double fallback) {
    id value = info[[ @"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix ]];
    double result = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    return isfinite(result) ? result : fallback;
}

static NSString *text(NSDictionary *info, NSString *suffix) {
    id value = info[[ @"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix ]];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static void emit(NSArray *items) {
    if ([lastOutput isEqual:items]) return;
    lastOutput = [items copy];
    NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
    if (data) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout); }
}

static NSDictionary *clientCounts(NSArray *clients) {
    NSMutableDictionary *counts = [NSMutableDictionary new];
    for (id client in clients) {
        if (![client respondsToSelector:@selector(bundleIdentifier)] || ![client respondsToSelector:@selector(processIdentifier)] || [client processIdentifier] <= 0) continue;
        NSString *bundle = [client bundleIdentifier];
        if (bundle.length) counts[bundle] = @([counts[bundle] unsignedIntegerValue] + 1);
    }
    return counts;
}

static BOOL sameTarget(id requested, id resolved) {
    if (![requested respondsToSelector:@selector(client)] || ![requested respondsToSelector:@selector(player)] ||
        ![resolved respondsToSelector:@selector(client)] || ![resolved respondsToSelector:@selector(player)]) return NO;
    id a = [requested client], b = [resolved client];
    id ap = [requested player], bp = [resolved player];
    if (![a respondsToSelector:@selector(processIdentifier)] || ![b respondsToSelector:@selector(processIdentifier)] ||
        ![a respondsToSelector:@selector(bundleIdentifier)] || ![b respondsToSelector:@selector(bundleIdentifier)] ||
        ![ap respondsToSelector:@selector(identifier)] || ![bp respondsToSelector:@selector(identifier)]) return NO;
    return [a processIdentifier] > 0 && [a processIdentifier] == [b processIdentifier] &&
        [[a bundleIdentifier] length] > 0 && [[a bundleIdentifier] isEqual:[b bundleIdentifier]] &&
        [[ap identifier] length] > 0 && [[ap identifier] isEqual:[bp identifier]];
}

static void query(void);
static void query(void) {
    if (querying) { dirty = YES; return; }
    querying = YES;
    queryDeadline = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, worker);
    dispatch_source_set_timer(queryDeadline, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(queryDeadline, ^{
        // Fail closed instead of retaining stale playing rows after a stuck IPC.
        emit(@[]);
        exit(1);
    });
    dispatch_resume(queryDeadline);
    getClients(worker, ^(NSArray *clients) {
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray *rows = [NSMutableArray new];
        NSDictionary *counts = clientCounts(clients);
        NSString *currentBundle = [[[NSClassFromString(@"MRNowPlayingRequest") localNowPlayingPlayerPath] client] bundleIdentifier];
        // Bound each event to a small number of recent system clients. No artwork requests.
        for (id client in [clients subarrayWithRange:NSMakeRange(0, MIN(clients.count, 8))]) {
            if (![client respondsToSelector:@selector(bundleIdentifier)]) continue;
            dispatch_group_enter(group);
            getPlayerForClient(client, [NSClassFromString(@"MROrigin") localOrigin], worker, ^(id player, NSError *playerError) {
            if (playerError || ![player respondsToSelector:@selector(identifier)] || ![[player identifier] length]) { dispatch_group_leave(group); return; }
            // The system default-player token is a wildcard. Bind the actual client-specific player.
            id requestedPath = [[NSClassFromString(@"MRPlayerPath") alloc] initWithOrigin:[NSClassFromString(@"MROrigin") localOrigin] client:client player:player];
            resolvePlayerPath(requestedPath, worker, ^(id path, NSError *resolutionError) {
            if (resolutionError || !sameTarget(requestedPath, path)) { dispatch_group_leave(group); return; }
            id request = [[NSClassFromString(@"MRNowPlayingRequest") alloc] initWithPlayerPath:path];
            if (![request respondsToSelector:@selector(requestNowPlayingInfoOnQueue:completion:)] ||
                ![request respondsToSelector:@selector(requestPlaybackStateOnQueue:completion:)] ||
                ![request respondsToSelector:@selector(requestSupportedCommandsOnQueue:completion:)]) { dispatch_group_leave(group); return; }
            [request requestPlaybackStateOnQueue:worker completion:^(unsigned int state, NSError *stateError) {
                if (stateError || (state != 1 && state != 2)) { dispatch_group_leave(group); return; }
                [request requestNowPlayingInfoOnQueue:worker completion:^(NSDictionary *info, NSError *infoError) {
                    if (infoError || ![info isKindOfClass:NSDictionary.class] || !text(info, @"Title").length) { dispatch_group_leave(group); return; }
                    [request requestSupportedCommandsOnQueue:worker completion:^(NSArray *commands, NSError *commandError) {
                        BOOL play = NO, pause = NO, next = NO, previous = NO, seek = NO;
                        for (id command in commands) {
                            if (![command respondsToSelector:@selector(command)] || ![command respondsToSelector:@selector(isEnabled)] || ![command isEnabled]) continue;
                            switch ([command command]) { case 0: play=YES; break; case 1: pause=YES; break; case 4: next=YES; break; case 5: previous=YES; break; case 24: seek=YES; break; default: break; }
                        }
                        NSData *pathData = [path data];
                        if (pathData) {
                            double elapsed = number(info, @"ElapsedTime", 0);
                            id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                            double epoch = [timestamp isKindOfClass:NSDate.class] ? [timestamp timeIntervalSince1970] : NSDate.date.timeIntervalSince1970;
                            NSString *bundle = [client bundleIdentifier] ?: @"";
                            // macOS resolves duplicate instances by app identity; never control an ambiguous source.
                            if ([counts[bundle] unsignedIntegerValue] != 1) play = pause = next = previous = seek = NO;
                            [rows addObject:@{@"id":[pathData base64EncodedStringWithOptions:0], @"title":text(info,@"Title"), @"artist":text(info,@"Artist"),
                                @"source":[client displayName] ?: bundle, @"isPlaying":@((BOOL)(state == 1)), @"playbackState":@(state), @"sourceBundleIdentifier":bundle, @"sourceProcessIdentifier":@([client processIdentifier]), @"canPlay":@(play), @"elapsed":@(elapsed), @"duration":@(number(info,@"Duration",0)),
                                @"timestamp":@(epoch), @"playbackRate":@(number(info,@"PlaybackRate",1)),
                                @"canSeek":@(seek), @"canPause":@(pause), @"canNext":@(next), @"canPrevious":@(previous), @"priority":@([bundle isEqual:currentBundle]?0:1)}];
                        }
                        dispatch_group_leave(group);
                    }];
                }];
            }];
            });
            });
        }
        dispatch_group_notify(group, worker, ^{
            [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSComparisonResult result = [a[@"priority"] compare:b[@"priority"]];
                return result == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : result;
            }];
            if (queryDeadline) { dispatch_source_cancel(queryDeadline); queryDeadline = nil; }
            emit(rows);
            querying = NO;
            if (dirty) { dirty = NO; query(); }
        });
    });
}

void status_trio_media_stream(void) { @autoreleasepool {
    if (!loadRuntime()) { emit(@[]); return; }
    worker = dispatch_queue_create("StatusTrio.MediaBridge", DISPATCH_QUEUE_SERIAL);
    registerNotifications(worker);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", @"kMRMediaRemoteNowPlayingPlaybackStateDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(worker, ^{ query(); });
        }];
    }
    dispatch_async(worker, ^{ query(); });
    dispatch_main();
} }

void status_trio_media_command(void) { @autoreleasepool {
    if (!loadRuntime()) { puts("{\"ok\":false}"); return; }
    const char *encoded = getenv("STATUS_TRIO_MEDIA_PATH");
    const char *rawCommand = getenv("STATUS_TRIO_MEDIA_COMMAND");
    if (!encoded || !rawCommand) { puts("{\"ok\":false}"); return; }
    int command = atoi(rawCommand);
    if (command != 0 && command != 1 && command != 4 && command != 5 && command != 24) { puts("{\"ok\":false}"); return; }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:@(encoded) options:0];
    id path = data ? [[NSClassFromString(@"MRPlayerPath") alloc] initWithData:data] : nil;
    if (!path || !sendToPlayer) { puts("{\"ok\":false}"); return; }
    id targetClient = [path client];
    if (![targetClient respondsToSelector:@selector(bundleIdentifier)] || ![targetClient respondsToSelector:@selector(processIdentifier)] || [targetClient processIdentifier] <= 0) { puts("{\"ok\":false}"); return; }
    NSString *targetBundle = [targetClient bundleIdentifier];
    if (!targetBundle.length) { puts("{\"ok\":false}"); return; }
    dispatch_semaphore_t validation = dispatch_semaphore_create(0);
    __block BOOL uniqueTarget = NO;
    getClients(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(NSArray *clients) {
        if ([clientCounts(clients)[targetBundle] unsignedIntegerValue] == 1) {
            for (id client in clients) {
                if ([[client bundleIdentifier] isEqual:targetBundle] && [client processIdentifier] == [targetClient processIdentifier]) uniqueTarget = YES;
            }
        }
        dispatch_semaphore_signal(validation);
    });
    if (dispatch_semaphore_wait(validation, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0 || !uniqueTarget) { puts("{\"ok\":false}"); return; }
    // Resolve before dispatch and reject any redirection to the global/current player.
    id intendedPlayer = [path player];
    NSString *intendedIdentifier = [intendedPlayer respondsToSelector:@selector(identifier)] ? [intendedPlayer identifier] : nil;
    if (!intendedIdentifier.length) { puts("{\"ok\":false}"); return; }
    dispatch_semaphore_t resolution = dispatch_semaphore_create(0);
    __block id exactPath = nil;
    resolvePlayerPath(path, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(id resolved, NSError *error) {
        if (!error && sameTarget(path, resolved)) exactPath = resolved;
        dispatch_semaphore_signal(resolution);
    });
    if (dispatch_semaphore_wait(resolution, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0 || !exactPath) { puts("{\"ok\":false}"); return; }
    NSDictionary *options = @{};
    if (command == 24) {
        CFStringRef const *positionKey = dlsym(mediaHandle, "kMRMediaRemoteOptionPlaybackPosition");
        const char *rawPosition = getenv("STATUS_TRIO_MEDIA_POSITION");
        char *end = NULL;
        double position = rawPosition ? strtod(rawPosition, &end) : -1;
        if (!positionKey || !*positionKey || !rawPosition || end == rawPosition || *end != '\0' || !isfinite(position) || position < 0) { puts("{\"ok\":false}"); return; }
        options = @{(__bridge NSString *)*positionKey:@(position)};
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL completed = NO;
    BOOL accepted = sendToPlayer((unsigned int)command, options, exactPath, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^(id result) {
        NSArray *results = [result isKindOfClass:NSArray.class] ? result : (result ? @[result] : @[]);
        Class resultClass = NSClassFromString(@"MRCommandResult");
        completed = results.count > 0;
        for (id entry in results) {
            if (!resultClass || ![entry isKindOfClass:resultClass] ||
                ![entry respondsToSelector:@selector(error)] || ![entry respondsToSelector:@selector(sendError)] ||
                [entry error] != nil || [entry sendError] != 0) { completed = NO; break; }
        }
        dispatch_semaphore_signal(sem);
    });
    if (!accepted || dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)) != 0) completed = NO;
    puts(completed ? "{\"ok\":true}" : "{\"ok\":false}");
} }

#import "MediaRemoteBridge.h"

typedef void (*GetNowPlayingInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetApplicationIsPlayingFunction)(dispatch_queue_t, void (^)(BOOL));
typedef void (*GetApplicationPIDFunction)(dispatch_queue_t, void (^)(int32_t));

static NSString * const ChihiroIsPlayingKey = @"ChihiroIsPlaying";
static NSString * const ChihiroApplicationPIDKey = @"ChihiroApplicationPID";

static CFBundleRef ChihiroMediaRemoteBundle(void) {
    static CFBundleRef bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
        bundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)url);
    });
    return bundle;
}

NSDictionary * _Nullable ChihiroCopyNowPlayingSnapshot(void) {
    CFBundleRef bundle = ChihiroMediaRemoteBundle();
    if (bundle == NULL) {
        return nil;
    }

    GetNowPlayingInfoFunction getInfo = (GetNowPlayingInfoFunction)
        CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingInfo"));
    GetApplicationIsPlayingFunction getIsPlaying = (GetApplicationIsPlayingFunction)
        CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying"));
    GetApplicationPIDFunction getPID = (GetApplicationPIDFunction)
        CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingApplicationPID"));

    if (getInfo == NULL) {
        return nil;
    }

    __block NSDictionary *information;
    __block BOOL isPlaying = NO;
    __block int32_t applicationPID = 0;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t callbackQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    dispatch_group_enter(group);
    getInfo(callbackQueue, ^(NSDictionary *value) {
        information = [value copy];
        dispatch_group_leave(group);
    });

    if (getIsPlaying != NULL) {
        dispatch_group_enter(group);
        getIsPlaying(callbackQueue, ^(BOOL value) {
            isPlaying = value;
            dispatch_group_leave(group);
        });
    }

    if (getPID != NULL) {
        dispatch_group_enter(group);
        getPID(callbackQueue, ^(int32_t value) {
            applicationPID = value;
            dispatch_group_leave(group);
        });
    }

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC);
    dispatch_group_wait(group, timeout);
    if (information == nil) {
        return nil;
    }

    NSMutableDictionary *snapshot = [information mutableCopy];
    snapshot[ChihiroIsPlayingKey] = @(isPlaying);
    snapshot[ChihiroApplicationPIDKey] = @(applicationPID);
    return [snapshot copy];
}

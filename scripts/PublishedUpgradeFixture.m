#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#include <sys/stat.h>

// This separate application is the process Sparkle may terminate. The host it
// updates is a private copy of published Vale; ordinary Vale is never launched.
@interface PublishedUpgradeDelegate : NSObject <NSApplicationDelegate, SPUUpdaterDelegate>
@property(nonatomic, strong) SPUUpdater *updater;
@property(nonatomic, strong) SPUStandardUserDriver *userDriver;
@property(nonatomic, strong) NSURL *root;
@property(nonatomic, strong) NSDictionary *request;
@property(nonatomic) BOOL finishing;
@end

@implementation PublishedUpgradeDelegate
- (void)record:(NSString *)event values:(NSDictionary *)values {
    NSMutableDictionary *receipt = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
    receipt[@"event"] = event;
    receipt[@"time"] = @([NSDate date].timeIntervalSince1970);
    receipt[@"pid"] = @(NSProcessInfo.processInfo.processIdentifier);
    receipt[@"fixtureBundleID"] = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:NULL];
    NSURL *file = [self.root URLByAppendingPathComponent:[NSString stringWithFormat:@"event-%@-%@.json", event, NSUUID.UUID.UUIDString]];
    [data writeToURL:file options:NSDataWritingAtomic error:NULL];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:NULL];
}
- (NSDictionary *)errorCodes:(NSError *)error {
    NSMutableArray *chain = [NSMutableArray array];
    NSSet *domains = [NSSet setWithArray:@[SUSparkleErrorDomain, NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain]];
    for (NSUInteger depth = 0; error != nil && depth < 8; depth++) {
        [chain addObject:@{@"domain": [domains containsObject:error.domain] ? error.domain : @"other", @"code":@(error.code)}];
        error = error.userInfo[NSUnderlyingErrorKey];
    }
    return @{@"errorChain":chain};
}
- (BOOL)matchesExpectedItem:(SUAppcastItem *)item {
    return [item.versionString isEqualToString:self.request[@"expectedBuild"]] &&
        [item.fileURL.absoluteString isEqualToString:self.request[@"expectedURL"]] &&
        item.deltaUpdates.count == 0;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSString *rootPath = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PublishedUpgradeRoot"];
    if (![rootPath isKindOfClass:NSString.class]) { [NSApp terminate:nil]; return; }
    self.root = [[NSURL fileURLWithPath:rootPath] URLByResolvingSymlinksInPath];
    struct stat attributes;
    BOOL safeRoot = [self.root.URLByDeletingLastPathComponent.path isEqualToString:@"/private/tmp"] &&
        [self.root.lastPathComponent hasPrefix:@"vale-published-upgrade."] &&
        lstat(self.root.path.fileSystemRepresentation, &attributes) == 0 &&
        S_ISDIR(attributes.st_mode) && attributes.st_uid == getuid() && (attributes.st_mode & 0077) == 0;
    if (!safeRoot) { [NSApp terminate:nil]; return; }
    self.request = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[self.root URLByAppendingPathComponent:@"prepared.json"]] options:0 error:NULL];
    NSString *fixtureID = self.request[@"fixtureBundleID"];
    NSString *defaultsID = self.request[@"defaultsDomain"];
    NSURL *hostURL = [self.root URLByAppendingPathComponent:@"installed/Vale.app"];
    NSURL *driverURL = [self.root URLByAppendingPathComponent:@"Published Upgrade.app"];
    BOOL identitySafe = [fixtureID hasPrefix:@"local.vale.publishedupgrade."] &&
        [defaultsID isEqualToString:[fixtureID stringByAppendingString:@".host"]] &&
        [NSBundle.mainBundle.bundleIdentifier isEqualToString:fixtureID] &&
        [NSBundle.mainBundle.bundleURL.URLByResolvingSymlinksInPath.path isEqualToString:driverURL.path] &&
        [self.request[@"root"] isEqualToString:self.root.path];
    if (!identitySafe) { [NSApp terminate:nil]; return; }
    // A normal running Vale could share the SDK's host-ID installer service.
    // Refuse the test rather than stopping or interfering with that application.
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.lilt.companion"].count != 0) {
        [self record:@"refused-running-vale" values:@{}]; [NSApp terminate:nil]; return;
    }
    NSBundle *host = [NSBundle bundleWithURL:hostURL];
    NSDictionary *info = host.infoDictionary;
    BOOL hostSafe = [host.bundleIdentifier isEqualToString:@"local.lilt.companion"] &&
        [info[@"SUDefaultsDomain"] isEqualToString:defaultsID] &&
        [info[@"SUFeedURL"] isEqualToString:@"https://github.com/AgarwalAarush/Vale/releases/latest/download/appcast.xml"] &&
        [info[@"SUPublicEDKey"] isEqualToString:@"LIo57815YwKGJzwijcc6uut6Q4H5nShI95d99T6O4Z8="] &&
        [info[@"SURequireSignedFeed"] isEqual:@YES] &&
        [info[@"SUVerifyUpdateBeforeExtraction"] isEqual:@YES] &&
        [info[@"SUSignedFeedFailureExpirationInterval"] isEqual:@0];
    if (!hostSafe) { [self record:@"refused-host" values:@{}]; [NSApp terminate:nil]; return; }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:defaultsID];
    if ([defaults objectForKey:@"PublishedUpgradeSentinel"] != nil) {
        [self record:@"refused-reused-defaults" values:@{}]; [NSApp terminate:nil]; return;
    }
    [defaults setObject:@"Generated published-upgrade preference" forKey:@"PublishedUpgradeSentinel"];
    [defaults synchronize];
    [self record:@"driver-started" values:@{@"hostBuild":info[@"CFBundleVersion"] ?: @"", @"defaultsDomain":defaultsID}];
    self.userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:host delegate:nil];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:host applicationBundle:NSBundle.mainBundle userDriver:self.userDriver delegate:self];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        [self record:@"sdk-start-failed" values:[self errorCodes:error]]; [NSApp terminate:nil]; return;
    }
    [self record:@"updater-started" values:@{@"automaticChecks":@(self.updater.automaticallyChecksForUpdates), @"automaticDownloads":@(self.updater.automaticallyDownloadsUpdates)}];
    // Fresh isolated defaults and the copied published plist drive scheduling.
    // No manual check, insecure feed override, or runtime preference setter.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self record:@"self-timeout" values:@{}]; [NSApp terminate:nil];
    });
}
- (void)updater:(SPUUpdater *)updater didFinishLoadingAppcast:(SUAppcast *)appcast {
    (void)updater; (void)appcast; [self record:@"verified-production-feed-loaded" values:@{}];
}
- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item {
    (void)updater;
    [self record:@"valid-update-found" values:@{@"expectedItem":@([self matchesExpectedItem:item]), @"build":item.versionString ?: @""}];
}
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item updateCheck:(SPUUpdateCheck)check error:(NSError *__autoreleasing *)error {
    (void)updater; (void)check;
    if ([self matchesExpectedItem:item]) return YES;
    if (error) *error = [NSError errorWithDomain:@"ValePublishedUpgrade" code:1 userInfo:nil];
    [self record:@"unexpected-feed-item-rejected" values:@{}];
    return NO;
}
- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request {
    (void)updater;
    BOOL permitted = [self matchesExpectedItem:item] && [request.URL.absoluteString isEqualToString:self.request[@"expectedURL"]];
    [self record:@"archive-request" values:@{@"expectedHTTPSURL":@(permitted)}];
    if (!permitted) request.URL = nil;
}
- (void)updater:(SPUUpdater *)updater didDownloadUpdate:(SUAppcastItem *)item {
    (void)updater; (void)item; [self record:@"archive-downloaded" values:@{}];
}
- (void)updater:(SPUUpdater *)updater didExtractUpdate:(SUAppcastItem *)item {
    (void)updater; (void)item; [self record:@"archive-verified-and-extracted" values:@{}];
}
- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item {
    (void)updater; (void)item; [self record:@"will-install" values:@{}];
}
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))handler {
    (void)updater; (void)item; (void)handler;
    [self record:@"ready-on-quit" values:@{}];
    if (!self.finishing) {
        self.finishing = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self record:@"normal-driver-quit" values:@{}]; [NSApp terminate:nil];
        });
    }
    return NO;
}
- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater {
    (void)updater; [self record:@"sdk-relaunch-disabled" values:@{}]; return NO;
}
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    (void)updater; [self record:@"sdk-abort" values:[self errorCodes:error]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    (void)updater;
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:error ? [self errorCodes:error] : @{}];
    values[@"checkType"] = @(check);
    [self record:@"sdk-cycle-finished" values:values];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        PublishedUpgradeDelegate *delegate = [PublishedUpgradeDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
        (void)delegate;
    }
    return 0;
}

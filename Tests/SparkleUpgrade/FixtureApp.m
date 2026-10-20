#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

#ifndef FIXTURE_BUILD
#error FIXTURE_BUILD must be explicitly defined as 1 or 2
#endif

@interface FixtureDelegate : NSObject <NSApplicationDelegate, SPUUpdaterDelegate>
@property(nonatomic, strong) SPUStandardUpdaterController *controller;
@property(nonatomic, strong) NSURL *root;
@property(nonatomic) BOOL finishing;
@end

@implementation FixtureDelegate
- (void)record:(NSString *)event values:(NSDictionary *)values {
    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
    record[@"event"] = event;
    record[@"compiledBuild"] = @(FIXTURE_BUILD);
    record[@"bundleID"] = NSBundle.mainBundle.bundleIdentifier ?: @"";
    record[@"time"] = @([NSDate date].timeIntervalSince1970);
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *name = [NSString stringWithFormat:@"%@-%@.json", event, NSUUID.UUID.UUIDString];
    [data writeToURL:[self.root URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:NULL];
}
- (NSDictionary *)errorReceipt:(NSError *)error {
    NSMutableArray *chain = [NSMutableArray array];
    BOOL signatureRelated = NO;
    for (NSUInteger depth = 0; error != nil && depth < 8; depth++) {
        [chain addObject:@{ @"domain": error.domain ?: @"", @"code": @(error.code) }];
        NSString *description = error.localizedDescription.lowercaseString;
        signatureRelated |= [description containsString:@"signature"] || [description containsString:@"signed"] || [description containsString:@"eddsa"];
        error = error.userInfo[NSUnderlyingErrorKey];
    }
    return @{ @"errorChain": chain, @"signatureRelated": @(signatureRelated) };
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSString *rootString = [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureRoot"];
    self.root = [[NSURL fileURLWithPath:rootString ?: @""] URLByResolvingSymlinksInPath];
    NSString *prefix = [self.root.path stringByAppendingString:@"/"];
    NSString *appPath = NSBundle.mainBundle.bundleURL.URLByResolvingSymlinksInPath.path;
    NSString *parent = self.root.URLByDeletingLastPathComponent.path;
    BOOL safe = [self.root.lastPathComponent hasPrefix:@"vale-sparkle-fixture."] &&
        ([parent isEqualToString:@"/private/tmp"] || [parent isEqualToString:@"/tmp"]) &&
        [appPath hasPrefix:prefix] &&
        [NSBundle.mainBundle.bundleIdentifier hasPrefix:@"local.vale.sparklefixture."];
    if (!safe) { [NSApp terminate:nil]; return; }
    [self record:@"did-launch" values:@{}];
    NSURL *store = [self.root URLByAppendingPathComponent:@"user-data" isDirectory:YES];
    NSURL *chat = [store URLByAppendingPathComponent:@"sessions.json"];
    NSURL *attachment = [store URLByAppendingPathComponent:@"attachment.txt"];
#if FIXTURE_BUILD == 1
    [NSFileManager.defaultManager createDirectoryAtURL:store withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    [@"{\"draft\":\"Unsent public fixture draft\",\"note\":\"Retained public fixture note\"}" writeToURL:chat atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"Retained public fixture attachment" writeToURL:attachment atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [NSUserDefaults.standardUserDefaults setObject:@"Retained public fixture preference" forKey:@"FixturePreference"];
#endif
#if FIXTURE_BUILD == 2
    [self record:@"new-did-launch" values:@{}];
    NSDictionary *restored = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:chat] options:0 error:NULL];
    NSString *retained = [NSString stringWithContentsOfURL:attachment encoding:NSUTF8StringEncoding error:NULL];
    [self record:@"user-data-restored" values:@{
        @"draftPreserved": @([restored[@"draft"] isEqualToString:@"Unsent public fixture draft"]),
        @"notePreserved": @([restored[@"note"] isEqualToString:@"Retained public fixture note"]),
        @"attachmentPreserved": @([retained isEqualToString:@"Retained public fixture attachment"]),
        @"preferencePreserved": @([[NSUserDefaults.standardUserDefaults stringForKey:@"FixturePreference"] isEqualToString:@"Retained public fixture preference"])
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
#else
    self.controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
    NSError *error = nil;
    if (![self.controller.updater startUpdater:&error]) {
        [self record:@"start-failed" values:[self errorReceipt:error]];
        [NSApp terminate:nil];
        return;
    }
    [self record:@"updater-started" values:@{
        @"automaticChecks": @(self.controller.updater.automaticallyChecksForUpdates),
        @"automaticDownloads": @(self.controller.updater.automaticallyDownloadsUpdates)
    }];
    // No manual check API: a fresh nonce domain and plist defaults exercise the SDK's startup scheduler.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self record:@"self-timeout" values:@{}];
        [NSApp terminate:nil];
    });
#endif
}
- (void)updater:(SPUUpdater *)updater didDownloadUpdate:(SUAppcastItem *)item {
    (void)updater; (void)item; [self record:@"did-download" values:@{}];
}
- (void)updater:(SPUUpdater *)updater didExtractUpdate:(SUAppcastItem *)item {
    (void)updater; (void)item; [self record:@"did-extract" values:@{}];
}
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))handler {
    (void)updater; (void)item;
    [self record:@"ready-on-quit" values:@{}];
    if (self.finishing) return NO;
    self.finishing = YES;
    BOOL relaunch = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureMode"] isEqualToString:@"relaunch"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (relaunch) { [self record:@"sdk-install-relaunch-requested" values:@{}]; handler(); }
        else { [self record:@"normal-quit-requested" values:@{}]; [NSApp terminate:nil]; }
    });
    return relaunch;
}
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    (void)updater;
    [self record:@"sdk-abort" values:[self errorReceipt:error]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    (void)updater;
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:error ? [self errorReceipt:error] : @{}];
    values[@"checkType"] = @(check);
    [self record:@"cycle-finished" values:values];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        FixtureDelegate *delegate = [FixtureDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
        (void)delegate;
    }
    return 0;
}

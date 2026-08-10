#import "VimbAppDelegate.h"
#import "VimbConfig.h"
#import "VimbMenu.h"

@interface VimbAppDelegate () <NSApplicationDelegate>
@end

@implementation VimbAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _controllers = [NSMutableArray array];
    }
    return self;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // Cmd-W closes a window but should NOT quit the app (per macOS browser
    // convention); the app stays in the dock until Cmd-Q.
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSApp.mainMenu = [VimbMenu mainMenu];
    [self newWindowForCommandLineArguments];
    // Source the user rc file; commands are routed to the commands' listener.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VimbConfig shared] sourceConfigFile];
    });
    [NSApp activateIgnoringOtherApps:YES];
}

- (BrowserWindowController *)openNewWindowWithURL:(NSString *)urlValue {
    BrowserWindowController *wc = [[BrowserWindowController alloc] init];
    [self.controllers addObject:wc];
    wc.windowReleasedHandler = ^(NSWindowController *w) {
        [self.controllers removeObject:(BrowserWindowController *)w];
    };
    [wc showWindow:nil];
    if (urlValue.length) {
        [wc loadURL:urlValue];
    }
    return wc;
}

- (void)newWindowForCommandLineArguments {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSString *url = nil;
    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg hasPrefix:@"-"]) { continue; }
        url = arg;
        break;
    }
    if (url == nil) {
        url = [defaults stringForKey:@"startpage"];
    }
    if (url == nil || url.length == 0) {
        url = @"about:blank";
    }
    [self openNewWindowWithURL:url];
}

- (void)newWindow:(id)sender {
    // Cmd-N opens a new window loading the configured start page (like Safari).
    NSString *start = [VimbConfig shared].settings[@"home-page"];
    if (![start isKindOfClass:[NSString class]] || !start.length) { start = @"about:blank"; }
    [self openNewWindowWithURL:start];
}

// Clicking the Dock icon reopens a window when the app has none (like Safari).
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    if (!hasVisibleWindows) {
        [self newWindow:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    return hasVisibleWindows;
}

@end

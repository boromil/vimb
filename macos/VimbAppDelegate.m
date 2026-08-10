#import "VimbAppDelegate.h"
#import "VimbConfig.h"

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
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self newWindowForCommandLineArguments];
    // Source the user rc file; commands are routed to the commands' listener.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VimbConfig shared] sourceConfigFile];
    });
    [NSApp activateIgnoringOtherApps:YES];
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

    BrowserWindowController *wc = [[BrowserWindowController alloc] init];
    [self.controllers addObject:wc];
    wc.windowReleasedHandler = ^(NSWindowController *w) {
        [self.controllers removeObject:(BrowserWindowController *)w];
    };
    [wc showWindow:nil];
    [wc loadURL:url];
}

- (void)newWindow:(id)sender {
    BrowserWindowController *wc = [[BrowserWindowController alloc] init];
    [self.controllers addObject:wc];
    wc.windowReleasedHandler = ^(NSWindowController *w) {
        [self.controllers removeObject:(BrowserWindowController *)w];
    };
    [wc showWindow:nil];
}

@end

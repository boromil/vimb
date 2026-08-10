#import "BrowserWindowController.h"
#import "KeyboardWebView.h"
#import "TabView.h"
#import "VimbEx.h"
#import "VimbConfig.h"
#import "VimbEngine.h"

static const CGFloat kStatusHeight = 24.0;

@interface BrowserWindowController () <VimDelegate, KeyboardWebViewDelegate, NSTextFieldDelegate, VimbExActor>
@property(nonatomic, strong) VimController *vim;
@property(nonatomic, strong) VimbEx *exEngine;
@property(nonatomic, strong) VimbRegisters *registers;
@property(nonatomic, strong) VimbMarks *marks;
@property(nonatomic, strong) NSMutableArray<VimbTab *> *tabs;
@property(nonatomic, weak) VimbTab *activeTab;

@property(nonatomic, strong) NSStackView *tabBar;
@property(nonatomic, strong) NSMutableArray<NSButton *> *tabButtons;
@property(nonatomic, strong) NSView *webContainer;
@property(nonatomic, strong) NSTextField *commandField;
@property(nonatomic, strong) NSTextField *statusField;
@property(nonatomic, strong) NSView *currentWebviewHolder;
@property(nonatomic, copy, nullable) NSString *commandPrefix;
@end

@implementation BrowserWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1100, 760)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"vimb";
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.minSize = NSMakeSize(640, 400);

    self = [super initWithWindow:window];
    if (self) {
        _vim = [[VimController alloc] init];
        _vim.delegate = self;
        _exEngine = [[VimbEx alloc] init];
        _exEngine.actor = self;
        _registers = [[VimbRegisters alloc] init];
        _marks = [[VimbMarks alloc] init];
        _tabs = [NSMutableArray array];
        _tabButtons = [NSMutableArray array];
        [self buildUI];
        window.delegate = self;
        [window center];
        [self newTabInWindow];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    // Vertical layout: tab bar on top, web view in middle, status bar below.
    NSStackView *v = [NSStackView stackViewWithViews:@[]];
    v.orientation = NSUserInterfaceLayoutOrientationVertical;
    v.alignment = NSLayoutAttributeWidth;
    v.spacing = 0;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:content.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    // Tab bar
    self.tabBar = [NSStackView stackViewWithViews:@[]];
    self.tabBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.tabBar.alignment = NSLayoutAttributeCenterY;
    self.tabBar.spacing = 4;
    self.tabBar.edgeInsets = NSEdgeInsetsMake(4, 8, 4, 8);
    NSView *tabHost = [[NSView alloc] init];
    tabHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabBar.translatesAutoresizingMaskIntoConstraints = NO;
    [tabHost addSubview:self.tabBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabBar.leadingAnchor constraintEqualToAnchor:tabHost.leadingAnchor constant:8],
        [self.tabBar.trailingAnchor constraintLessThanOrEqualToAnchor:tabHost.trailingAnchor constant:-8],
        [self.tabBar.topAnchor constraintEqualToAnchor:tabHost.topAnchor],
        [self.tabBar.bottomAnchor constraintEqualToAnchor:tabHost.bottomAnchor],
    ]];
    NSButton *closeBtn = [NSButton buttonWithTitle:@"×" target:self action:@selector(closeActiveTabAction:)];
    NSButton *newBtn = [NSButton buttonWithTitle:@"+" target:self action:@selector(newTabAction:)];
    [self.tabBar addArrangedSubview:closeBtn];
    [self.tabBar addArrangedSubview:newBtn];

    [v addArrangedSubview:tabHost];

    // Web container
    self.webContainer = [[NSView alloc] init];
    self.webContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [v addArrangedSubview:self.webContainer];

    // Status + command line
    self.statusField = [NSTextField labelWithString:@""];
    self.statusField.font = [NSFont systemFontOfSize:12];
    self.statusField.textColor = [NSColor secondaryLabelColor];
    self.statusField.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusField.translatesAutoresizingMaskIntoConstraints = NO;

    self.commandField = [[NSTextField alloc] init];
    self.commandField.delegate = self;
    self.commandField.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.commandField.hidden = YES;
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *status = [NSStackView stackViewWithViews:@[self.statusField, self.commandField]];
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.spacing = 8;
    status.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *statusHost = [[NSView alloc] init];
    statusHost.translatesAutoresizingMaskIntoConstraints = NO;
    [statusHost addSubview:status];
    [NSLayoutConstraint activateConstraints:@[
        [status.leadingAnchor constraintEqualToAnchor:statusHost.leadingAnchor constant:8],
        [status.trailingAnchor constraintEqualToAnchor:statusHost.trailingAnchor constant:-8],
        [status.topAnchor constraintEqualToAnchor:statusHost.topAnchor],
        [status.bottomAnchor constraintEqualToAnchor:statusHost.bottomAnchor],
    ]];
    NSLayoutConstraint *sh = [statusHost.heightAnchor constraintEqualToConstant:kStatusHeight];
    sh.priority = NSLayoutPriorityRequired;
    [NSLayoutConstraint activateConstraints:@[sh]];
    [v addArrangedSubview:statusHost];

    // Fill: webContainer expands.
    [v setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
}

#pragma mark - Tabs

- (void)newTabInWindow {
    KeyboardWebView *wv = [[KeyboardWebView alloc] initWithFrame:self.webContainer.bounds];
    wv.vbDelegate = self;
    VimbTab *tab = [[VimbTab alloc] initWithWebView:wv];
    [self.tabs addObject:tab];
    [self setActiveTab:tab];
    [self rebuildTabBar];
}

- (void)openNewTab { [self newTabInWindow]; }

- (void)setActiveTab:(VimbTab *)tab {
    [self.currentWebviewHolder removeFromSuperview];
    self.currentWebviewHolder = nil;
    _activeTab = tab;   // assign ivar directly to avoid recursive setter call
    self.currentWebviewHolder = tab.view;
    tab.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.webContainer addSubview:tab.view];
    [NSLayoutConstraint activateConstraints:@[
        [tab.view.leadingAnchor constraintEqualToAnchor:self.webContainer.leadingAnchor],
        [tab.view.trailingAnchor constraintEqualToAnchor:self.webContainer.trailingAnchor],
        [tab.view.topAnchor constraintEqualToAnchor:self.webContainer.topAnchor],
        [tab.view.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor],
    ]];
    self.window.title = tab.title ?: @"vimb";
    [self.window makeFirstResponder:tab.view];
    [self updateStatus];
}

- (void)closeActiveTabAction:(id)sender { [self closeActiveTab]; }
- (void)newTabAction:(id)sender { [self newTabInWindow]; }
- (void)closeActiveTab {
    if (self.tabs.count == 0) { return; }
    NSUInteger idx = [self.tabs indexOfObject:self.activeTab];
    VimbTab *closed = self.activeTab;
    if (closed.url.absoluteString.length) {
        [[VimbConfig shared].closedStore push:closed.url.absoluteString
                                         max:(NSUInteger)[VimbConfig shared].closedMax];
    }
    [self.tabs removeObject:closed];
    if (self.tabs.count == 0) {
        [self.window close];
        return;
    }
    NSUInteger next = MIN(idx, self.tabs.count - 1);
    [self rebuildTabBar];
    [self setActiveTab:self.tabs[next]];
}

- (void)nextTab {
    if (self.tabs.count == 0) { return; }
    NSUInteger idx = [self.tabs indexOfObject:self.activeTab];
    NSUInteger next = (idx + 1) % self.tabs.count;
    [self setActiveTab:self.tabs[next]];
    [self rebuildTabBar];
}

- (void)prevTab {
    if (self.tabs.count == 0) { return; }
    NSUInteger idx = [self.tabs indexOfObject:self.activeTab];
    NSUInteger next = (idx + self.tabs.count - 1) % self.tabs.count;
    [self setActiveTab:self.tabs[next]];
    [self rebuildTabBar];
}

- (void)selectTabAtIndex:(NSUInteger)index {
    if (index < self.tabs.count) {
        [self setActiveTab:self.tabs[index]];
        [self rebuildTabBar];
    }
}

- (void)tabButtonClicked:(NSButton *)sender {
    NSUInteger idx = sender.tag;
    [self selectTabAtIndex:idx];
}

- (void)rebuildTabBar {
    for (NSButton *b in self.tabButtons) { [self.tabBar removeArrangedSubview:b]; }
    [self.tabButtons removeAllObjects];
    NSUInteger activeIdx = self.activeTab ? [self.tabs indexOfObject:self.activeTab] : NSNotFound;
    for (NSUInteger i = 0; i < self.tabs.count; i++) {
        VimbTab *t = self.tabs[i];
        NSString *title = [t.title length] ? t.title : @"New Tab";
        NSButton *b = [NSButton buttonWithTitle:title target:self action:@selector(tabButtonClicked:)];
        b.tag = (NSInteger)i;
        b.bezelStyle = NSBezelStyleInline;
        b.font = [NSFont systemFontOfSize:11];
        b.controlSize = NSControlSizeSmall;
        if (i == activeIdx) {
            b.state = NSControlStateValueOn;
            b.contentTintColor = [NSColor controlAccentColor];
        }
        b.lineBreakMode = NSLineBreakByTruncatingTail;
        NSLayoutConstraint *w = [b.widthAnchor constraintLessThanOrEqualToConstant:150];
        w.priority = NSLayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[w]];
        [self.tabBar addArrangedSubview:b];
        [self.tabButtons addObject:b];
    }
}

#pragma mark - Loading

- (void)loadURL:(NSString *)urlValue { [self loadURL:urlValue inNewTab:NO]; }

- (void)loadURL:(NSString *)urlValue inNewTab:(BOOL)newTab {
    NSURL *url = [self normalizeURL:urlValue];
    if (newTab) { [self newTabInWindow]; }
    [self.activeTab.webView loadRequest:[NSURLRequest requestWithURL:url]];
    [self updateStatus];
}

- (NSURL *)normalizeURL:(NSString *)input {
    NSString *s = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"\\ " withString:@" "];
    if (s.length == 0) { return [NSURL URLWithString:@"about:blank"]; }
    NSRange r = [s rangeOfString:@"://"];
    if (r.location == NSNotFound && ![s hasPrefix:@"about:"] && ![s hasPrefix:@"file:"]) {
        BOOL hasSpace = [s rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound;
        if (hasSpace) {
            // Treat as a search query.
            NSString *enc = [s stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            return [NSURL URLWithString:[NSString stringWithFormat:@"https://duckduckgo.com/?q=%@", enc]];
        }
        if (![s containsString:@"."]) {
            // Likely a host without dot; still try loading.
            s = [@"https://" stringByAppendingString:s];
        }
        NSURL *u = [NSURL URLWithString:s];
        if (u && u.scheme.length == 0) {
            s = [@"https://" stringByAppendingString:s];
            u = [NSURL URLWithString:s];
        }
        return u ?: [NSURL URLWithString:@"about:blank"];
    }
    NSURL *url = [NSURL URLWithString:s];
    return url ?: [NSURL URLWithString:@"about:blank"];
}

#pragma mark - Vim action helpers

- (void)goBack { [self.activeTab.webView goBack]; }
- (void)goForward { [self.activeTab.webView goForward]; }
- (void)reloadPage { [self.activeTab.webView reload]; }

- (void)commandLineExecuted:(NSString *)line {
    // The command line text may include its leading prompt char.
    if (line.length == 0) { return; }
    unichar p = [line characterAtIndex:0];
    NSString *rest = [line substringFromIndex:1];
    switch (p) {
        case ':':
            [self.exEngine runCommand:rest];
            break;
        case '/':
            [self.activeTab.webView findString:rest forwardDirection:YES];
            [[VimbConfig shared].searchStore prepend:rest max:100];
            break;
        case '?':
            [self.activeTab.webView findString:rest forwardDirection:NO];
            [[VimbConfig shared].searchStore prepend:rest max:100];
            break;
        default:
            // open/find without a prompt char (e.g. from o/O).
            if ([line hasPrefix:@"open "]) {
                [self.exEngine runCommand:line];
            } else if (p == ';' || p == 'g') {
                [self.activeTab.webView toggleHints];
            } else {
                [self.exEngine runCommand:line];
            }
            break;
    }
}

#pragma mark - VimbExActor

- (void)exOpen:(NSString *)arg newTab:(BOOL)newTab {
    [self loadURL:arg inNewTab:newTab];
    if (!newTab) { [self recordHistory:arg]; }
}

- (void)recordHistory:(NSString *)url {
    [[VimbConfig shared].historyStore prepend:url max:(NSUInteger)[VimbConfig shared].historyMax];
}

- (void)exSet:(NSString *)fullArg {
    // :set name=value | :set name | :set no[name] | :set name? | :set add+=.. etc
    NSString *a = [fullArg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (a.length == 0) { [self showMessage:@"set requires an argument" error:YES]; return; }
    VimbConfig *cfg = [VimbConfig shared];
    // 'set all' prints everything
    if ([a isEqualToString:@"all"]) {
        NSMutableArray *lines = [NSMutableArray array];
        [cfg.settings enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop){
            (void)stop;
            [lines addObject:[NSString stringWithFormat:@"%@ = %@", k, v]];
        }];
        [self showMessage:[lines componentsJoinedByString:@"  "] error:NO];
        return;
    }
    // Parse modifiers: += -= ^= ! ? (format: name+=value)
    NSArray<NSArray<NSString *> *> *parts = nil;
    if ([a containsString:@"+="]) { parts = [self split:a on:@"+="]; }
    else if ([a containsString:@"-="]) { parts = [self split:a on:@"-="]; }
    else if ([a containsString:@"^="]) { parts = [self split:a on:@"^="]; }
    else if ([a containsString:@"="]) { parts = [self split:a on:@"="]; }
    else if ([a hasSuffix:@"?"]) { [self showMessage:[NSString stringWithFormat:@"%@ = %@", a, cfg.settings[a]] error:NO]; return; }
    else if ([a hasPrefix:@"no"]) {
        NSString *name = [a substringFromIndex:2];
        [cfg applySetting:name value:@NO];
        return;
    }
    else if ([a hasPrefix:@"inv"]) {
        NSString *name = [a substringFromIndex:3];
        id old = cfg.settings[name] ?: @NO;
        [cfg applySetting:name value:@(![old boolValue])];
        return;
    }

    if (parts) {
        NSString *name = parts[0][0];
        NSString *val = parts[0][1];
        if (val.length == 0) { // :set name -> on / show
            id cur = cfg.settings[name];
            [self showMessage:[NSString stringWithFormat:@"%@ = %@", name, cur ?: @"unset"] error:NO];
            return;
        }
        NSNumber *num = @(val.doubleValue);
        [cfg applySetting:name value:num];
    } else {
        // :set name (boolean -> on)
        [cfg applySetting:a value:@YES];
    }

    // scroll-step is re-read from the config on each scroll, so nothing to do here.
}

- (NSArray<NSArray<NSString *> *> *)split:(NSString *)s on:(NSString *)sep {
    NSArray *sp = [s componentsSeparatedByString:sep];
    if (sp.count == 2) { return @[@[sp[0], sp[1]]]; }
    return nil;
}

- (void)exCloseActiveTab { [self closeActiveTab]; }
- (void)exNextTab { [self nextTab]; }
- (void)exPrevTab { [self prevTab]; }
- (void)exFirstTab { [self selectTabAtIndex:0]; }
- (void)exLastTab { [self selectTabAtIndex:(self.tabs.count - 1)]; }
- (void)exReload { [self reloadPage]; }
- (void)exStop { [self.activeTab.webView stopLoading:nil]; }
- (void)exHome { [self vimOpenHome]; }
- (void)exQuit { [self.window close]; }
- (void)exQuitAll { [NSApp terminate:nil]; }
- (void)exEval:(NSString *)js {
    [self.activeTab.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        NSString *out = error ? error.localizedDescription : ([result isKindOfClass:[NSString class]] ? result : [result description]);
        if (![result isKindOfClass:[NSNull class]] && result) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showMessage:out error:error != nil]; });
        }
    }];
}
- (void)exMessage:(NSString *)msg error:(BOOL)error {
    if (msg.length) { [self showMessage:msg error:error]; }
}
- (void)exSavePage {
    [self showMessage:@"save: not supported on native backend yet" error:YES];
}
- (void)exRegisterList {
    NSString *hist = [[VimbConfig shared].commandStore lines].firstObject ?: @"";
    [self showMessage:[NSString stringWithFormat:@"registers: \":%@@\"", hist] error:NO];
}
- (void)exShowMessages { [self showMessage:@"no messages" error:NO]; }

- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title {
    NSString *line = url;
    if (title.length) { line = [NSString stringWithFormat:@"%@ %@", url, title]; }
    [[VimbConfig shared].bookmarkStore prepend:line max:0];
    [self showMessage:[NSString stringWithFormat:@"added bookmark %@", url] error:NO];
}

- (void)exBookmarkRemove:(NSString *)match {
    NSString *target = match;
    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    BOOL removed = NO;
    for (NSString *line in [[VimbConfig shared].bookmarkStore lines]) {
        NSString *url = [line componentsSeparatedByString:@" "].firstObject;
        if ([url hasPrefix:target]) { removed = YES; continue; }
        [remaining addObject:line];
    }
    if (!removed) {
        [remaining removeObject:target];
    }
    [[VimbConfig shared].bookmarkStore writeAll:remaining];
    [self showMessage:removed ? @"bookmark removed" : @"no bookmark removed" error:!removed];
}

- (NSArray<NSDictionary *> *)bookmarksByPrefix:(NSString *)prefix {
    NSMutableArray<NSDictionary *> *r = [NSMutableArray array];
    for (NSString *line in [[VimbConfig shared].bookmarkStore lines]) {
        NSString *url = [line componentsSeparatedByString:@" "].firstObject;
        NSString *title = line.length > url.length ? [line substringFromIndex:url.length + 1] : @"";
        if (prefix.length == 0 || [url hasPrefix:prefix] || [title hasPrefix:prefix]) {
            [r addObject:@{@"url": url, @"title": title}];
        }
    }
    return r;
}



- (void)showMessage:(NSString *)message error:(BOOL)error {
    self.statusField.stringValue = message ?: @"";
    self.statusField.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.statusField.stringValue isEqualToString:message]) {
            self.statusField.stringValue = @"";
        }
    });
}

- (void)updateStatus {
    if (!self.activeTab) { return; }
    NSString *url = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString ?: @"";
    self.statusField.stringValue = url;
}

#pragma mark - Window delegate

- (void)windowWillClose:(NSNotification *)notification {
    [self.activeTab.webView stopLoading:nil];
    if (self.windowReleasedHandler) {
        self.windowReleasedHandler(self);
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (self.activeTab) {
        [self.window makeFirstResponder:self.activeTab.view];
    }
}

#pragma mark - KeyboardWebViewDelegate

- (VimController *)vimControllerForView:(KeyboardWebView *)view {
    return self.vim;
}

- (void)webView:(KeyboardWebView *)view didUpdateTitle:(NSString *)title {
    VimbTab *tab = [self tabForWebView:view];
    if (tab) {
        tab.title = title ?: @"New Tab";
        [self rebuildTabBar];
        if (tab == self.activeTab) { self.window.title = title ?: @"vimb"; }
    }
}

- (void)webView:(KeyboardWebView *)view didUpdateProgress:(double)progress {
    // Reflect load progress in the status bar text; the WKWebView titlebar
    // progress indicator is not available on this SDK.
    if (view == self.activeTab.webView && progress > 0.0 && progress < 1.0) {
        self.statusField.stringValue = [NSString stringWithFormat:@"loading… %d%%", (int)(progress * 100)];
    }
}

- (void)webView:(KeyboardWebView *)view didFinishLoadWithURL:(NSURL *)url {
    if (view == self.activeTab.webView) {
        self.activeTab.url = url;
        [self updateStatus];
        [self.window makeFirstResponder:view];
    }
    if (url && url.absoluteString.length && ![url.absoluteString isEqualToString:@"about:blank"]) {
        [self recordHistory:url.absoluteString];
    }
}

- (void)webView:(KeyboardWebView *)view didReceiveMessage:(NSDictionary *)payload {
    NSString *t = payload[@"t"];
    if ([t isEqualToString:@"hintnone"]) {
        [self showMessage:@"No hints available" error:NO];
        [self.vim reset];
    } else if ([t isEqualToString:@"hintready"]) {
        [self showMessage:[NSString stringWithFormat:@"%@ hints", payload[@"n"]] error:NO];
    } else if ([t isEqualToString:@"hintpending"]) {
        // keep hint mode active
    } else if ([t isEqualToString:@"loaderror"]) {
        [self showMessage:payload[@"s"] ?: @"Page load error" error:YES];
    } else if ([t isEqualToString:@"download-done"]) {
        [self showMessage:@"Download finished" error:NO];
    } else if ([t isEqualToString:@"hintyank"]) {
        NSString *url = payload[@"url"] ?: @"";
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:url forType:NSPasteboardTypeString];
        [self.registers set:url forKey:'"'];
        [self showMessage:[NSString stringWithFormat:@"yanked %@", url] error:NO];
    } else if ([t isEqualToString:@"hintopen"]) {
        NSString *url = payload[@"url"] ?: @"";
        if (url.length) {
            [self loadURL:url inNewTab:YES];
            [self showMessage:[NSString stringWithFormat:@"opened in new tab %@", url] error:NO];
        }
    }
}

#pragma mark - Helpers

- (VimbTab *)tabForWebView:(KeyboardWebView *)view {
    for (VimbTab *t in self.tabs) {
        if (t.webView == view) { return t; }
    }
    return nil;
}

- (void)vimOpenPrompt:(NSString *)prompt mode:(VimMode)mode {
    if (mode == VimModeHint) {
        // Hint mode keeps the webview focused so hint keys route to JS.
        self.commandField.hidden = YES;
        if (self.activeTab) { [self.window makeFirstResponder:self.activeTab.view]; }
        return;
    }
    self.commandPrefix = prompt;
    if ([prompt hasPrefix:@"open "] || [prompt hasPrefix:@"tabopen "]) {
        // o/t prefills the command line with the open prefix.
        self.commandField.stringValue = prompt;
    } else {
        self.commandField.stringValue = @"";
    }
    self.commandField.placeholderString = [prompt isEqualToString:@":"] ? @"command" : @"search";
    self.commandField.hidden = NO;
    [self.window makeFirstResponder:self.commandField];
}

#pragma mark - VimDelegate

// Mirrors vimb's normal_scroll -> vbscroll() dispatch (src/scripts/scroll.js).
- (void)vimScrollMode:(unichar)mode count:(NSUInteger)count {
    if (count == 0) { count = 1; }
    CGFloat step = 128;
    switch (mode) {
        case 'j': [self.activeTab.webView scrollBy:0 y:(step * count)]; break;
        case 'k': [self.activeTab.webView scrollBy:0 y:-(step * count)]; break;
        case 'h': [self.activeTab.webView scrollBy:-(step * count) y:0]; break;
        case 'l': [self.activeTab.webView scrollBy:(step * count) y:0]; break;
        case 0x14: /* ^P unused here */ [self.activeTab.webView scrollBy:0 y:(step * count)]; break;
        case ' ':
        case 0x06: /* ^F */ [self pagedScrollDown:count]; break;
        case 0x02: /* ^B */ [self pagedScrollUp:count]; break;
        case 0x15: /* ^U */ [self pagedScrollHalfUp:count]; break;
        case 0x04: /* ^D */ [self pagedScrollHalfDown:count]; break;
        case 'G': [self.activeTab.webView scrollToBottom]; break;
        case 'g':
            if (count >= 1 && count <= 99) { [self.activeTab.webView scrollToPercent:count]; }
            else { [self.activeTab.webView scrollToTop]; }
            break;
        case '0': [self.activeTab.webView scrollToX:0]; break;
        case '$': [self.activeTab.webView scrollToXEnd]; break;
        case 'H': [self.activeTab.webView scrollToTop]; break;
        case 'M': [self.activeTab.webView scrollToMiddle]; break;
        case 'L': [self.activeTab.webView scrollToBottom]; break;
        default: break;
    }
}

- (void)pagedScrollDown:(NSUInteger)count {
    NSString *js = [NSString stringWithFormat:@"window.scrollBy(0, window.innerHeight*%lu)", (unsigned long)count];
    [self.activeTab.webView evaluateJavaScript:js completionHandler:nil];
}
- (void)pagedScrollUp:(NSUInteger)count {
    NSString *js = [NSString stringWithFormat:@"window.scrollBy(0, -window.innerHeight*%lu)", (unsigned long)count];
    [self.activeTab.webView evaluateJavaScript:js completionHandler:nil];
}
- (void)pagedScrollHalfDown:(NSUInteger)count {
    NSString *js = [NSString stringWithFormat:@"window.scrollBy(0, window.innerHeight*%lu/2)", (unsigned long)count];
    [self.activeTab.webView evaluateJavaScript:js completionHandler:nil];
}
- (void)pagedScrollHalfUp:(NSUInteger)count {
    NSString *js = [NSString stringWithFormat:@"window.scrollBy(0, -window.innerHeight*%lu/2)", (unsigned long)count];
    [self.activeTab.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)vimGoBack { [self goBack]; }
- (void)vimGoForward { [self goForward]; }
- (void)vimReload { [self reloadPage]; }
- (void)vimStop { [self.activeTab.webView stopLoading:nil]; }
- (void)vimOpenURL:(NSString *)urlValue inNewTab:(BOOL)newTab { [self loadURL:urlValue inNewTab:newTab]; }
- (void)vimOpenHome {
    // 'U'/'u' reopens the most recently closed page (vimb normal_open).
    NSString *closed = [[VimbConfig shared].closedStore top];
    if (closed.length) {
        [self loadURL:closed inNewTab:NO];
        [[VimbConfig shared].closedStore removeLine:closed];
        return;
    }
    NSString *start = [[VimbConfig shared].settings objectForKey:@"home-page"];
    if (![start isKindOfClass:[NSString class]] || !start.length) { start = @"about:blank"; }
    [self loadURL:start inNewTab:NO];
}

- (void)vimGoHomeURL {
    // Go up one path segment (vimb normal_descent).
    NSURL *u = self.activeTab.webView.URL;
    if (!u || u.absoluteString.length == 0) { return; }
    NSURL *res = [u URLByDeletingLastPathComponent];
    if (res.absoluteString.length == 0) {
        res = u;
    }
    NSString *resStr = res.absoluteString;
    if (resStr.length && ![resStr hasSuffix:@"/"]) {
        resStr = [resStr stringByAppendingString:@"/"];
    }
    [self loadURL:resStr inNewTab:NO];
}
- (void)vimSearch:(NSString *)query forward:(BOOL)forward {
    self.commandField.hidden = YES;
    [self.activeTab.webView findString:query forwardDirection:forward];
    [self showMessage:[NSString stringWithFormat:@"Search: %@", query] error:NO];
}
- (void)vimSearchDirection:(NSInteger)dir {
    // dir is a count; sign indicates direction. Re-run the last query.
    [self.activeTab.webView findNextDirection:(dir >= 0)];
}
- (void)vimSearchSelectionForward:(BOOL)forward {
    [self showMessage:@"search selection: select text first" error:NO];
}
- (void)vimFire {
    NSString *js = @"getSelection().anchorNode && getSelection().anchorNode.parentNode && getSelection().anchorNode.parentNode.click();";
    [self.activeTab.webView evaluateJavaScript:js completionHandler:nil];
}
- (void)vimFocusLastActive {
    [self.activeTab.webView focusLastActiveElement];
}
- (void)vimFocusInput {
    [self.activeTab.webView focusFirstInput];
}
- (void)vimEnterPassThrough {
    [self showMessage:@"pass-through not implemented on native backend" error:YES];
}
- (void)vimYankURI {
    NSString *url = self.activeTab.url.absoluteString ?: @"";
    [self.registers set:url forKey:'"'];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:url forType:NSPasteboardTypeString];
    [self showMessage:[NSString stringWithFormat:@"yanked %@", url] error:NO];
}
- (void)vimZoom:(BOOL)in {
    CGFloat f = self.activeTab.webView.magnification;
    f = in ? f + 0.1 : MAX(0.5, f - 0.1);
    self.activeTab.webView.magnification = f;
}
- (void)vimIncrement:(BOOL)up {
    [self showMessage:up ? @"" : @"" error:NO];
}
- (void)vimQuit {
    [self.window close];
}
- (void)vimOpenClipboard:(NSString *)counter {
    NSString *text = nil;
    if (counter.length && ![counter isEqualToString:@"0"] && ![counter isEqualToString:@"\0"]) {
        text = [self.registers get:[counter characterAtIndex:0]];
    }
    if (!text) {
        text = [self.registers get:'"'];
    }
    if (!text) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        text = [pb stringForType:NSPasteboardTypeString];
    }
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length) {
        [self loadURL:text inNewTab:NO];
    } else {
        [self showMessage:@"no register content" error:NO];
    }
    (void)counter;
}

- (void)vimNextTab { [self nextTab]; }
- (void)vimPrevTab { [self prevTab]; }
- (void)vimGotoTab:(NSUInteger)index {
    if (index == NSNotFound) { [self selectTabAtIndex:self.tabs.count - 1]; }
    else { [self selectTabAtIndex:index]; }
}
- (void)vimGotoTabFromLast:(NSInteger)count {
    NSUInteger last = self.tabs.count - 1;
    NSUInteger idx = (count > 1) ? (NSUInteger)MAX(0, (NSInteger)last - (count - 1)) : last;
    [self selectTabAtIndex:idx];
}
- (void)vimNewTab { [self newTabInWindow]; }
- (void)vimCloseTab { [self closeActiveTab]; }
- (void)vimToggleHints { [self.activeTab.webView toggleHints]; }
- (void)vimEnterHints:(NSString *)mode { [self.activeTab.webView toggleHints:mode]; }
- (void)vimHintKey:(NSString *)key { [self.activeTab.webView sendHintKey:key]; }
- (void)vimShowMessage:(NSString *)message error:(BOOL)error { [self showMessage:message error:error]; }
- (void)vimFocusWebView {
    if (self.activeTab) { [self.window makeFirstResponder:self.activeTab.view]; }
    self.commandField.hidden = YES;
}

#pragma mark - Command field (NSTextFieldDelegate)

- (void)controlTextDidChange:(NSNotification *)obj { }
- (void)controlTextDidEndEditing:(NSNotification *)obj { }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.commandField) {
        if (commandSelector == @selector(insertNewline:)) {
            NSString *line = self.commandField.stringValue;
            VimMode m = self.vim.mode;
            self.commandField.hidden = YES;
            if (m == VimModeCommand) { [self commandLineExecuted:line]; }
            else if (m == VimModeSearch) { [self.vim commandLineCommitted:line]; }
            [self.vim reset];
            [self.window makeFirstResponder:self.activeTab.view];
            return YES;
        }
        if (commandSelector == @selector(cancelOperation:)) {
            self.commandField.hidden = YES;
            [self.vim reset];
            [self.window makeFirstResponder:self.activeTab.view];
            return YES;
        }
        if (commandSelector == @selector(insertTab:)) {
            [self completeCommandField];
            return YES;
        }
    }
    return NO;
}

// Tab completion for the command line: completes :open/:bdelete urls from
// history+bookmarks+closed, and :set names from the settings registry.
- (void)completeCommandField {
    NSString *line = self.commandField.stringValue;
    VimMode m = self.vim.mode;
    if (m == VimModeSearch) { return; }
    NSMutableArray<NSString *> *cands = [NSMutableArray array];

    if ([line hasPrefix:@"open "] || [line hasPrefix:@"tabopen "]) {
        BOOL tab = [line hasPrefix:@"tabopen "];
        NSString *prefix = [line substringFromIndex:(tab ? 8 : 5)];
        for (NSDictionary *b in [self bookmarksByPrefix:prefix]) { [cands addObject:b[@"url"]]; }
        for (NSString *h in [[VimbConfig shared].historyStore lines]) { if ([h hasPrefix:prefix] && ![cands containsObject:h]) [cands addObject:h]; }
        for (NSString *c in [[VimbConfig shared].closedStore lines]) { if ([c hasPrefix:prefix] && ![cands containsObject:c]) [cands addObject:c]; }
        if (cands.count == 1) {
            self.commandField.stringValue = [NSString stringWithFormat:@"%@%@", tab ? @"tabopen " : @"open ", cands[0]];
        } else if (cands.count > 1 && cands.count <= 8) {
            [self showMessage:[cands componentsJoinedByString:@"  "] error:NO];
        } else if (cands.count > 8) {
            [self showMessage:[NSString stringWithFormat:@"%lu completions", (unsigned long)cands.count] error:NO];
        }
    } else if ([line hasPrefix:@"bdelete "] || [line hasPrefix:@"bd "]) {
        NSString *prefix = [line containsString:@" "] ? [line substringFromIndex:([line rangeOfString:@" "].location + 1)] : @"";
        for (VimbTab *t in self.tabs) {
            NSString *turl = t.url.absoluteString ?: t.webView.URL.absoluteString ?: @"";
            NSString *ttitle = t.title ?: @"";
            if ([turl hasPrefix:prefix] || [ttitle hasPrefix:prefix]) {
                [cands addObject:[NSString stringWithFormat:@"%@ — %@", ttitle, turl]];
            }
        }
        if (cands.count == 1) {
            self.commandField.stringValue = line;
            [self showMessage:[NSString stringWithFormat:@"%lu matching tab(s)", (unsigned long)cands.count] error:NO];
        } else if (cands.count > 1) {
            [self showMessage:[cands componentsJoinedByString:@"  "] error:NO];
        }
    } else if ([line hasPrefix:@"set "]) {
        NSString *prefix = [line substringFromIndex:4];
        for (NSString *name in [VimbConfig shared].settings.allKeys) {
            if ([name hasPrefix:prefix]) { [cands addObject:name]; }
        }
        if (cands.count == 1) {
            self.commandField.stringValue = [NSString stringWithFormat:@"set %@", cands[0]];
        } else if (cands.count > 1 && cands.count <= 8) {
            [self showMessage:[cands componentsJoinedByString:@"  "] error:NO];
        }
    } else if ([line hasPrefix:@"shellcmd "]) {
        // no shell completion on native
    }
}

@end

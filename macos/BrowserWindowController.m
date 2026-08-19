#import "BrowserWindowController.h"
#import "VimbPath.h"
#import "KeyboardWebView.h"
#import "TabView.h"
#import "VimbEx.h"
#import "VimbConfig.h"
#import "VimbEngine.h"
#import "VimbHintEngine.h"
#import "VimbCommandField.h"
#import "VimbWindow.h"
#import "VimbTaskRunner.h"
#import "VimbEditor.h"
#import "VimbBookmarkBrowser.h"
#import "CompletionDropdown.h"
#import "CompletionCandidate.h"

@interface BrowserWindowController () <VimDelegate, KeyboardWebViewDelegate, NSTextFieldDelegate, VimbExActor, VimbCommandFieldDelegate>
@property(nonatomic, strong) VimController *vim;
@property(nonatomic, strong) VimbEx *exEngine;
@property(nonatomic, strong) VimbRegisters *registers;
@property(nonatomic, strong) VimbMarks *marks;
@property(nonatomic, strong) NSArray<NSString *> *exHistorySnapshot;
@property(nonatomic, assign) NSInteger exHistoryIndex;
// Completion session state for the dropdown (GTK parity: excomp).
// head = fixed part before the completed token (":open "), baseLine = the
// line as the user typed it (restored when stepping past the list edge).
@property(nonatomic, copy, nullable) NSString *completionHead;
@property(nonatomic, copy, nullable) NSString *completionBaseLine;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pendingMarkY;
@property(nonatomic, strong) NSMutableArray<VimbTab *> *tabs;
@property(nonatomic, weak) VimbTab *activeTab;

@property(nonatomic, strong) NSStackView *tabBar;
@property(nonatomic, strong) NSMutableArray<NSButton *> *tabButtons;
@property(nonatomic, strong) NSButton *addTabButton;
@property(nonatomic, strong) NSView *webContainer;
@property(nonatomic, strong) NSView *bottomBar;
@property(nonatomic, strong) NSLayoutConstraint *inputRowHeight;
@property(nonatomic, strong) VimbCommandField *commandField;
@property(nonatomic, strong) CompletionDropdown *completionDropdown;
@property(nonatomic, strong) NSTextField *statusField;
@property(nonatomic, strong) NSTextField *settingsIndicator;
@property(nonatomic, strong) NSView *currentWebviewHolder;
@property(nonatomic, copy, nullable) NSString *commandPrefix;
@property(nonatomic, assign) BOOL currentHintGmode;   // whether the active hint run is g-mode (keep-open)
@property(nonatomic, strong) NSLayoutConstraint *tabStripLeading;   // traffic-light inset (0 in fullscreen)
@end

@implementation BrowserWindowController

- (instancetype)init {
    NSWindow *window = [[VimbWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1100, 760)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                             NSWindowStyleMaskFullSizeContentView)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"vimb";
    // Modern unified chrome (HIG "Window anatomy" / Safari-style): the
    // titlebar is transparent and extends into the content so the tab strip
    // sits in the titlebar row; the traffic-light inset is reserved via the
    // safe-area guide. The title still shows in the Window menu / Mission
    // Control via the window's title property.
    window.titlebarAppearsTransparent = YES;
    // FullSizeContentView keeps drawing the title TEXT centered in the now
    // transparent titlebar — it lands on top of the tab strip (two texts
    // interleaved). Hide it; window.title still names the window in the
    // Window menu / Mission Control.
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    // vimb draws its own tab strip inside the titlebar row (Safari-style):
    // the strip is pinned to the content top and indented past the traffic
    // lights, so a separate toolbar/title-height hack is unnecessary.
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.minSize = NSMakeSize(640, 400);
    // vimb manages its own session state (like GTK vimb): opt out of macOS
    // persistent-window restoration. This also avoids the hidden "restore
    // windows?" crash modal AppKit shows at launch after a previous crash,
    // which blocks applicationDidFinishLaunching entirely.
    window.restorable = NO;

    self = [super initWithWindow:window];
    if (self) {
        _vim = [[VimController alloc] init];
        _vim.delegate = self;
        _exEngine = [[VimbEx alloc] init];
        _exEngine.actor = self;
        _exEngine.config = [VimbConfig shared];   // explicit; matches the lazy fallback
        _registers = [[VimbRegisters alloc] init];
        _marks = [[VimbMarks alloc] init];
        _pendingMarkY = [NSMutableDictionary dictionary];
        _exHistorySnapshot = @[];
        _exHistoryIndex = -1;
        _tabs = [NSMutableArray array];
        _tabButtons = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vimbRunCommand:)
                                                     name:@"VimbRunCommand" object:nil];
        [self buildUI];
        // Put the controller in the window's responder chain so menu actions
        // (Cmd-W close tab, Cmd-N new tab, back/forward, etc.) always resolve
        // to this controller regardless of the first responder / page state.
        window.nextResponder = self;
        window.delegate = self;
        [window center];
        [self newTabInWindow];
    }
    return self;
}

// Apply chrome settings (dark-mode/fullscreen/show-titlebar) once the window
// is loaded and can be safely manipulated, rather than during init before it
// is shown.
- (void)windowDidLoad {
    [super windowDidLoad];
    [self applyChromeSettings];
}

- (void)vimbRunCommand:(NSNotification *)note {
    NSString *cmd = note.userInfo[@"command"];
    if (cmd.length) {
        [self.exEngine runCommand:cmd];
    }
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    // Flex-column root: one plain container pinned to the content view's
    // safe-area guides (titlebar/fullscreen safe). The three rows attach to
    // IT, not directly to the window: pinning several views straight to the
    // window's guides during applicationDidFinishLaunching deadlocks Auto
    // Layout on this OS (the launch Apple event is still being handled).
    NSView *root = [[NSView alloc] init];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    // The tab strip lives INSIDE the (transparent) titlebar row. Pin root to
    // the content view's true edges, then indent the tab strip past the
    // traffic lights via the safe area. Everything else hangs off root.
    // (The safe-area top alone used to leave a full system-height titlebar
    // block above the strip, splitting the window into a dark title zone and
    // a light content zone — "the gui is fucked".)
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    // Row 1 — tab strip. An NSStackView as the vertical root is a trap: its
    // gravity-areas distribution hands all leftover height to the last
    // arranged view regardless of content-hugging priorities, collapsing
    // the web container to zero (blank viewport, self-dismissing completion
    // dropdown). The rows below form an explicit chain instead: tab strip
    // pinned to the top, bottom bar pinned to the bottom, web container
    // pinned between them (flex 1 1 auto).
    self.tabBar = [NSStackView stackViewWithViews:@[]];
    self.tabBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.tabBar.alignment = NSLayoutAttributeCenterY;
    self.tabBar.spacing = 6;
    self.tabBar.edgeInsets = NSEdgeInsetsMake(4, 8, 4, 8);
    // Let the strip hug its content (tabs + new-tab button) rather than
    // stretching the buttons across the full window width, which produced a
    // huge dead gap between tabs and an absurdly wide "active" tab.
    self.tabBar.distribution = NSStackViewDistributionGravityAreas;
    NSView *tabHost = [[NSView alloc] init];
    tabHost.translatesAutoresizingMaskIntoConstraints = NO;
    // Clip overflowing tab buttons at the window edge: with many tabs the
    // strip can get wider than the window, and without clipping the last
    // button paints outside the window frame (stray clipped label text at
    // the top-right corner).
    tabHost.wantsLayer = YES;
    tabHost.layer.masksToBounds = YES;
    self.tabBar.translatesAutoresizingMaskIntoConstraints = NO;
    [tabHost addSubview:self.tabBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabBar.leadingAnchor constraintEqualToAnchor:tabHost.leadingAnchor constant:8],
        // Trailing EQUALITY: the strip is exactly as wide as the host. With
        // many tabs the buttons compress (they truncate — compression
        // resistance 750 loses to this 1000-priority pin) instead of pushing
        // the strip — and the window — wider. A '<=' here let Auto Layout
        // grow the WINDOW to the strip's fitting width (verified: 25 tabs
        // resized the 1100pt window to 2229pt), and in non-resizable states
        // painted tab labels past the window borders.
        [self.tabBar.trailingAnchor constraintEqualToAnchor:tabHost.trailingAnchor constant:-8],
        [self.tabBar.topAnchor constraintEqualToAnchor:tabHost.topAnchor],
        [self.tabBar.bottomAnchor constraintEqualToAnchor:tabHost.bottomAnchor],
    ]];
    [root addSubview:tabHost];
    [NSLayoutConstraint activateConstraints:@[
        // Indent past the traffic lights: with FullSizeContentView the
        // safe-area guide resolves to x=0, so reserve the standard titlebar
        // leading inset (78pt = traffic lights + AppKit spacing) explicitly.
        // Fullscreen removes the lights, so the strip goes full-width there.
        [tabHost.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [tabHost.topAnchor constraintEqualToAnchor:root.topAnchor],
    ]];
    self.tabStripLeading = [tabHost.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:78];
    self.tabStripLeading.active = YES;

    // Row 2 — web container: the stretchy middle that fills everything
    // between the tab strip and the docked bottom bar.
    self.webContainer = [[NSView alloc] init];
    self.webContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.webContainer];

    // Row 3 — docked bottom bar (GTK parity: input line above status line in
    // one box, web view ending at its top edge — the page never renders
    // underneath the chrome). input-autohide collapses the input row while
    // idle, exactly like vimb hides its input box when unfocused.
    // Material: the bar uses the window-background material (HIG "Layout
    // and materials": bars get materials, not opaque fills) so it adapts to
    // light/dark automatically; a hairline separator marks its top edge.
    NSVisualEffectView *bottomBar = [[NSVisualEffectView alloc] init];
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBar.material = NSVisualEffectMaterialContentBackground;
    bottomBar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bottomBar.state = NSVisualEffectStateActive;
    [bottomBar addSubview:[self hairlineSeparator]];
    self.bottomBar = bottomBar;
    {
        NSBox *sep = bottomBar.subviews.lastObject;
        [NSLayoutConstraint activateConstraints:@[
            [sep.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor],
            [sep.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor],
            [sep.topAnchor constraintEqualToAnchor:bottomBar.topAnchor],
        ]];
    }
    [root addSubview:bottomBar];
    [NSLayoutConstraint activateConstraints:@[
        [bottomBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [bottomBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [bottomBar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [self.webContainer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.webContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.webContainer.topAnchor constraintEqualToAnchor:tabHost.bottomAnchor],
        [self.webContainer.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor],
    ]];

    // Input line: the command/search field spanning the bar.
    VimbCommandField *cmdField = [[VimbCommandField alloc] initWithFrame:NSZeroRect];
    cmdField.vbDelegate = self;
    cmdField.delegate = self;
    self.commandField = cmdField;
    self.commandField.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    // Flat input line (GTK parity: vimb's GtkEntry has no boxed chrome, and
    // HIG text guidance: fields inside bars shouldn't float as boxed
    // controls). A rounded-bezel NSTextField on the vibrancy bar rendered
    // as a hard black slab with a blue focus ring when active and a gray
    // slab when idle — visually detached from the bar. Borderless keeps
    // the text sitting directly on the bar material like Safari's bar.
    self.commandField.bezelStyle = NSTextFieldSquareBezel;
    self.commandField.bordered = NO;
    self.commandField.drawsBackground = NO;
    self.commandField.focusRingType = NSFocusRingTypeNone;
    self.commandField.controlSize = NSControlSizeRegular;
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomBar addSubview:self.commandField];

    // Status line: URL / transient messages in fixed rows, so text is always
    // fully visible and never clipped by the window boundary.
    self.statusField = [NSTextField labelWithString:@""];
    self.statusField.font = [NSFont systemFontOfSize:12];
    self.statusField.textColor = [NSColor secondaryLabelColor];
    self.statusField.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusField.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomBar addSubview:self.statusField];

    // status-bar-show-settings: right-aligned settings token (parity with
    // src/main.c STATUS_VARAIBLE_SHOW). Emptied (width 0) unless on, so the
    // status line can use the full width when it is off.
    self.settingsIndicator = [NSTextField labelWithString:@""];
    self.settingsIndicator.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.settingsIndicator.textColor = [NSColor tertiaryLabelColor];
    self.settingsIndicator.alignment = NSTextAlignmentRight;
    self.settingsIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsIndicator.hidden = YES;
    [bottomBar addSubview:self.settingsIndicator];

    self.inputRowHeight = [self.commandField.heightAnchor constraintEqualToConstant:26];
    self.inputRowHeight.active = YES;
    if ([self inputAutohide]) {
        self.inputRowHeight.constant = 0;
        self.commandField.hidden = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.commandField.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor constant:10],
        [self.commandField.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor constant:-12],
        [self.commandField.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:3],
        [self.statusField.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor constant:12],
        [self.statusField.trailingAnchor constraintLessThanOrEqualToAnchor:self.settingsIndicator.leadingAnchor constant:-8],
        // All-equality vertical chain: bar.top = cmd.top - 3,
        // status.top = cmd.bottom + 2, status.bottom = bar.bottom - 3 —
        // the bar's height is uniquely determined by its content (input row
        // height + status line). Any inequality here leaves the bar's height
        // free to stretch upward, and Auto Layout then hands the whole
        // window height to the bar and collapses the web container to zero.
        [self.statusField.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:2],
        [self.statusField.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-3],
        [self.settingsIndicator.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor constant:-12],
        [self.settingsIndicator.bottomAnchor constraintEqualToAnchor:self.statusField.bottomAnchor],
    ]];

    // Completion dropdown (parity with src/completion.c): an opaque list that
    // grows upward from the top of the input row while the user types a :/
    // command or a /? search. Its frame is set on every refresh via
    // presentRelativeToRect:inView:, which clamps it inside the container.
    CompletionDropdown *dd = [[CompletionDropdown alloc] initWithFrame:NSMakeRect(10, 0, 320, 160)];
    dd.hidden = YES;
    [self.webContainer addSubview:dd];
    self.completionDropdown = dd;
    // Every highlight change (Tab stepping or a mouse click) rewrites the input
    // line (GTK on_selection_changed -> completion_select). A click must not
    // steal focus from the input — GTK keeps the entry focused.
    __weak typeof(self) weakSelf = self;
    dd.onSelectionChanged = ^(NSString *value) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf setCommandFieldTextSuppressingCompletion:[strongSelf.completionHead stringByAppendingString:value]];
        if (![strongSelf.window.firstResponder isEqual:strongSelf.commandField.currentEditor]) {
            [strongSelf.window makeFirstResponder:strongSelf.commandField];
        }
    };

    // webContainer is the stretchy flex row: its height is whatever lies
    // between the two bars, and the bars size themselves from their content.
}

#pragma mark - Tabs

- (void)newTabInWindow {
    KeyboardWebView *wv = [[KeyboardWebView alloc] initWithFrame:self.webContainer.bounds];
    wv.vbDelegate = self;
    // Apply the default-zoom setting to new web views (parity: GTK applies
    // web-view zoom-level on creation; zz also resets to this value).
    NSInteger zoom = [[VimbConfig shared] getInt:@"default-zoom" defaultValue:100];
    if (zoom > 0 && zoom != 100) {
        wv.magnification = (CGFloat)zoom / 100.0;
    }
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
    // Insert the web view BELOW the completion dropdown so the dropdown and
    // the docked bottom bar render on top of the page.
    [self.webContainer addSubview:tab.view positioned:NSWindowBelow relativeTo:self.completionDropdown];
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
    // Clear every arranged subview (tabs AND the trailing new-tab button) so
    // the "+" stays grouped right after the last tab instead of drifting.
    for (NSView *sub in self.tabBar.arrangedSubviews.copy) {
        [self.tabBar removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }
    [self.tabButtons removeAllObjects];

    NSUInteger activeIdx = self.activeTab ? [self.tabs indexOfObject:self.activeTab] : NSNotFound;
    for (NSUInteger i = 0; i < self.tabs.count; i++) {
        VimbTab *t = self.tabs[i];
        NSString *title = [t.title length] ? t.title : @"New Tab";
        NSButton *b = [NSButton buttonWithTitle:title target:self action:@selector(tabButtonClicked:)];
        b.tag = (NSInteger)i;
        // Modern capsule tabs (HIG "Tabs" / Safari style): Rounded bezel
        // honors bezelColor, so the active tab is the accent-tinted capsule
        // and inactive tabs are quiet neutral capsules. Hover adds the
        // system hover effect via the cell; no layer hacks.
        b.bezelStyle = NSBezelStyleRounded;
        b.font = [NSFont systemFontOfSize:12 weight:(i == activeIdx ? NSFontWeightSemibold : NSFontWeightRegular)];
        b.controlSize = NSControlSizeSmall;
        b.imagePosition = NSNoImage;
        b.lineBreakMode = NSLineBreakByTruncatingTail;
        // Let the cell shrink below the full title (truncating with …) so
        // the strip can compress when there are many tabs. Without this the
        // title imposes a required minimum width, the strip's required
        // constraints become unsatisfiable, and AppKit grows the WINDOW to
        // the strip's fitting width (verified: 25 tabs resized a 1100pt
        // window to 2229pt).
        b.cell.wraps = NO;
        b.cell.truncatesLastVisibleLine = YES;
        // Cap each tab width so long titles truncate instead of pushing the
        // strip wide, and require the button to hug its own contents so the
        // stack lays tabs out left-to-right with no dead gap between them.
        [b setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [b setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSLayoutConstraint *w = [b.widthAnchor constraintLessThanOrEqualToConstant:180];
        w.priority = NSLayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[w]];
        if (i == activeIdx) {
            b.bezelColor = [NSColor controlAccentColor];
            b.contentTintColor = [NSColor whiteColor];
        } else {
            b.bezelColor = [NSColor quaternaryLabelColor];
            b.contentTintColor = [NSColor labelColor];
        }
        [self.tabBar addArrangedSubview:b];
        [self.tabButtons addObject:b];
    }

    // New-tab button grouped right after the last tab (Safari-style trailing
    // "+", but kept adjacent to the strip rather than stranded at the edge).
    if (!self.addTabButton) {
        self.addTabButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New Tab"]
                                               target:self action:@selector(newTabAction:)];
        self.addTabButton.bezelStyle = NSBezelStyleRounded;
        self.addTabButton.imagePosition = NSImageOnly;
        self.addTabButton.contentTintColor = [NSColor labelColor];
    }
    [self.tabBar addArrangedSubview:self.addTabButton];
}

#pragma mark - Loading

- (void)loadURL:(NSString *)urlValue { [self loadURL:urlValue inNewTab:NO]; }

- (void)loadURL:(NSString *)urlValue inNewTab:(BOOL)newTab {
    NSURL *url = [self normalizeURL:urlValue];
    if (newTab) { [self newTabInWindow]; }
    [self.activeTab.webView loadRequest:[NSURLRequest requestWithURL:url]];
    [self updateStatus];
}

// KeyboardWebViewDelegate: route a popup / target=_blank URL from the web view
// into a new tab (or the current tab when prevent-newwindow is set).
- (void)webView:(KeyboardWebView *)view openTargetURL:(NSString *)url newTab:(BOOL)newTab {
    [self loadURL:url inNewTab:newTab];
}

// Decide the URL to load, routing non-URL input through the search/shortcut
// engine (port of vb_load_uri). "https://example.com" loads direct; a bare
// "example.com" becomes http://example.com; a search query like "foo bar" or
// a single non-URL word is searched via the selected engine.
- (NSURL *)normalizeURL:(NSString *)input {
    NSString *uri = [[VimbConfig shared] loadURI:input ?: @""];
    NSURL *u = [NSURL URLWithString:uri];
    return u ?: [NSURL URLWithString:@"about:blank"];
}

#pragma mark - Vim action helpers

- (void)goBack { [self.activeTab.webView goBack]; }
- (void)goForward { [self.activeTab.webView goForward]; }
- (void)reloadPage { [self.activeTab.webView reload]; }

- (VimbExCmdResult)commandLineExecuted:(NSString *)line {
    // The command line text may include its leading prompt char.
    if (line.length == 0) { return VimbExCmdResultError; }
    unichar p = [line characterAtIndex:0];
    NSString *rest = [line substringFromIndex:1];
    switch (p) {
        case ':':
            [[VimbConfig shared].commandStore prepend:rest max:1000];
            return [self.exEngine runCommand:rest];
        case '/':
            [self.activeTab.webView findString:rest forwardDirection:YES];
            if (rest.length) { [[VimbConfig shared].searchStore prepend:rest max:100]; }
            [self showMessage:[NSString stringWithFormat:@"Search: %@", rest] error:NO];
            return VimbExCmdResultSuccess;
        case '?':
            [self.activeTab.webView findString:rest forwardDirection:NO];
            if (rest.length) { [[VimbConfig shared].searchStore prepend:rest max:100]; }
            [self showMessage:[NSString stringWithFormat:@"Search (backward): %@", rest] error:NO];
            return VimbExCmdResultSuccess;
        default:
            // open/find without a prompt char (e.g. from o/O).
            if ([line hasPrefix:@"open "]) {
                return [self.exEngine runCommand:line];
            } else if (p == ';' || p == 'g') {
                [self.activeTab.webView toggleHints];
                return VimbExCmdResultSuccess;
            } else {
                return [self.exEngine runCommand:line];
            }
    }
}

#pragma mark - VimbExActor

- (void)exOpen:(NSString *)arg newTab:(BOOL)newTab {
    [self loadURL:arg inNewTab:newTab];
    if (!newTab) { [self recordHistory:arg]; }
}

- (void)recordHistory:(NSString *)url {
    // GTK history_add: when history-max-items == 0, don't record at all.
    if ([VimbConfig shared].historyMax == 0) { return; }
    if (![[VimbConfig shared] shouldRecordURL:url]) { return; }
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
        // Validate string-polisted settings (GTK setters reject bad values and
        // keep the input for correction — setting.c cookie_accept/geolocation/
        // notification/hardware_acceleration_policy/download_path).
        if (![cfg validateSetting:name value:val]) {
            [self showMessage:[NSString stringWithFormat:@"invalid value for %@", name] error:YES];
            return;
        }
        // Coerce the string to the setting's declared storage type (char stays
        // NSString, int -> NSNumber(integer), bool -> NSNumber(boolean)). This
        // fixes the prior bug of flattening every value to a double, which
        // zeroed out char-typed settings like cookie-accept/edit-command.
        id coerced = [cfg coerceSettingValue:name stringValue:val];
        [cfg applySetting:name value:coerced];
    } else {
        // :set name (boolean -> on)
        [cfg applySetting:a value:@YES];
    }

    // scroll-step is re-read from the config on each scroll, so nothing to do here.
    [self applyChromeSettings];
}

// Apply window/app-level settings (:set dark-mode, :set fullscreen,
// :set show-titlebar) to the actual window, mirroring vimb's setters.
- (void)applyChromeSettings {
    VimbConfig *cfg = [VimbConfig shared];
    if ([cfg getBool:@"fullscreen" defaultValue:NO]) {
        if (!(self.window.styleMask & NSWindowStyleMaskFullScreen)) {
            [self.window toggleFullScreen:nil];
        }
    } else {
        if (self.window.styleMask & NSWindowStyleMaskFullScreen) {
            [self.window toggleFullScreen:nil];
        }
    }
    // show-titlebar: hide/show the standard titlebar via style mask.
    BOOL show = [cfg getBool:@"show-titlebar" defaultValue:YES];
    NSWindowStyleMask sm = self.window.styleMask;
    if (show && !(sm & NSWindowStyleMaskTitled)) {
        self.window.styleMask = sm | NSWindowStyleMaskTitled;
    } else if (!show && (sm & NSWindowStyleMaskTitled)) {
        self.window.styleMask = sm & ~NSWindowStyleMaskTitled;
    }
    // dark-mode: force the window (and so WKWebView content) into dark
    // appearance; prefers-color-scheme on pages follows the app appearance.
    // Off = follow the system (nil), NOT force-light: HIG apps track the
    // system appearance by default. GTK parity keeps dark-mode as an
    // opt-in override (setting.c dark_mode).
    if ([cfg getBool:@"dark-mode" defaultValue:NO]) {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    } else {
        self.window.appearance = nil;
    }
}

// Fullscreen removes the traffic lights, so the tab strip can span the full
// window width; the 78pt titlebar inset returns when the chrome reappears.
- (void)windowDidEnterFullScreen:(NSNotification *)note {
    (void)note;
    self.tabStripLeading.constant = 0;
}

- (void)windowDidExitFullScreen:(NSNotification *)note {
    (void)note;
    self.tabStripLeading.constant = 78;
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
- (void)exQuit:(BOOL)bang { (void)bang; [self.window close]; }
- (void)exQuitAll:(BOOL)bang { (void)bang; [NSApp terminate:nil]; }
- (void)exEval:(NSString *)js suppressOutput:(BOOL)suppress {
    __weak typeof(self) weakSelf = self;
    [self.activeTab.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (suppress) { return; }   // :eval! — don't print the result
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showMessage:[@"eval error: " stringByAppendingString:error.localizedDescription] error:YES];
            });
            return;
        }
        // Map the JS result to a status string without crashing on null/undefined.
        NSString *out = @"done";
        if ([result isKindOfClass:[NSString class]]) {
            out = ((NSString *)result).length ? result : @"done";
        } else if ([result isKindOfClass:[NSNumber class]]) {
            out = [result description];
        } else if (![result isKindOfClass:[NSNull class]]) {
            // Non-scalar objects (booleans, arrays, plain objects) are
            // returned by WKWebView as their description / WKScriptValue.
            out = [result description] ?: @"done";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showMessage:out error:NO];
        });
    }];
}
- (void)exShell:(NSString *)arg async:(BOOL)async {
    NSString *trimmed = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) {
        [self showMessage:@"shell: empty command" error:YES];
        return;
    }
    if (async) {
        // :shellcmd! — fire-and-forget async spawn (GTK g_spawn_command_line_async).
        NSError *err = nil;
        if (![VimbTaskRunner runAsync:trimmed environment:nil error:&err]) {
            [self showMessage:[@"shell: " stringByAppendingString:err.localizedDescription] error:YES];
        }
        return;
    }
    // Output is drained asynchronously by the runner — a child writing more
    // than one pipe buffer can never deadlock the termination handler.
    __weak typeof(self) weakSelf = self;
    [VimbTaskRunner run:trimmed environment:nil completion:^(NSString *out, NSString *err, int status) {
        NSString *msg;
        BOOL isError = NO;
        if (err.length) {
            msg = err;
            isError = YES;
        } else if (out.length) {
            msg = out;
        } else {
            msg = [NSString stringWithFormat:@"shell exited %d", status];
        }
        NSString *clean = [msg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length) {
            [weakSelf showMessage:clean error:isError];
        } else {
            [weakSelf showMessage:[NSString stringWithFormat:@"shell exited %d", status] error:NO];
        }
    }];
}
- (void)exClearData:(NSString *)arg {
    // :cleardata [types] or by default all types (port of ex_cleardata).
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    NSSet<NSString *> *types;
    NSArray<NSString *> *wanted = [arg componentsSeparatedByString:@","];
    if (arg.length == 0 || [arg isEqualToString:@"-"]) {
        types = [NSSet setWithArray:@[
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
        ]];
    } else {
        NSMutableSet *m = [NSMutableSet set];
        NSDictionary<NSString *, NSString *> *map = @{
            @"cookies": WKWebsiteDataTypeCookies,
            @"disk-cache": WKWebsiteDataTypeDiskCache,
            @"memory-cache": WKWebsiteDataTypeMemoryCache,
            @"offline-cache": WKWebsiteDataTypeOfflineWebApplicationCache,
            @"local-storage": WKWebsiteDataTypeLocalStorage,
            @"session-storage": WKWebsiteDataTypeSessionStorage,
            @"indexeddb-databases": WKWebsiteDataTypeIndexedDBDatabases,
            // hsts-cache has no public WKWebsiteDataType equivalent -> handled
            // up in VimbEx as a recognized (no-op) name, not erroring here.
            @"all": WKWebsiteDataTypeCookies,
        };
        for (NSString *t in wanted) {
            NSString *k = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (map[k]) {
                if ([k isEqualToString:@"all"]) {
                    [m addObjectsFromArray:@[WKWebsiteDataTypeCookies, WKWebsiteDataTypeDiskCache,
                        WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeLocalStorage,
                        WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases]];
                } else {
                    [m addObject:map[k]];
                }
            }
        }
        types = m;
    }
    __weak typeof(self) weakSelf = self;
    [store removeDataOfTypes:types modifiedSince:[NSDate distantPast]
        completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showMessage:[NSString stringWithFormat:@"cleared %lu data type(s)", (unsigned long)types.count] error:NO];
            });
        }];
}
- (void)exPrint {
    // :hardcopy opens the system print dialog for the current page.
    WKWebView *wv = self.activeTab.webView;
    NSPrintOperation *op = [wv printOperationWithPrintInfo:[NSPrintInfo sharedPrintInfo]];
    op.showsPrintPanel = YES;
    [op runOperation];
}
- (void)exMessage:(NSString *)msg error:(BOOL)error {
    if (msg.length) { [self showMessage:msg error:error]; }
}
- (void)exSavePage:(NSString *)path {
    NSString *uri = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString ?: @"";
    if (uri.length == 0 || [uri isEqualToString:@"about:blank"]) {
        [self showMessage:@"nothing to save" error:YES];
        return;
    }
    [self saveURI:uri path:path];
}

// Downloads `uri` to the given destination (or a derived name in download-path)
// and reports the result. Shared by :save and the 's' hint mode.
- (void)saveURI:(NSString *)uri path:(NSString *)path {
    if (uri.length == 0 || [uri isEqualToString:@"about:blank"]) {
        [self showMessage:@"nothing to save" error:YES];
        return;
    }
    NSString *destDir = [[VimbConfig shared] downloadsDirectory];
    NSString *dest = path;
    if (!dest.length) {
        NSString *name = [[uri lastPathComponent] stringByRemovingPercentEncoding];
        if (!name.length) { name = @"vimb-page.html"; }
        dest = [destDir stringByAppendingPathComponent:name];
    }
    NSURL *url = [NSURL URLWithString:uri];
    if (!url) { [self showMessage:@"invalid url" error:YES]; return; }
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        (void)resp;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                [weakSelf showMessage:[@"save failed: " stringByAppendingString:err ? err.localizedDescription : @"no data"] error:YES];
                return;
            }
            NSError *werr = nil;
            // Never overwrite an existing file: insert a `_N` suffix before the
            // extension (exact port of src/main.c's filename uniquification).
            NSString *unique = [weakSelf uniqueDestinationForPath:dest];
            [data writeToFile:unique options:NSDataWritingAtomic error:&werr];
            if (werr) { [weakSelf showMessage:[@"save failed: " stringByAppendingString:werr.localizedDescription] error:YES]; }
            else { [weakSelf showMessage:[@"saved to " stringByAppendingString:unique] error:NO]; }
        });
    }] resume];
}
// Returns a destination path that does not yet exist, inserting `_N` before
// the file extension (port of src/main.c's filename uniquification: `.tar.`
// counts as a two-dot extension). When the base name has no dot, appends `_N`.
// Pure path logic lives in VimbPath so it is unit-testable.
- (NSString *)uniqueDestinationForPath:(NSString *)path {
    return [VimbPath uniqueDestinationForPath:path];
}

- (void)exRegisterList {
    NSMutableString *str = [NSMutableString stringWithString:@"-- Register --"];
    NSString *dquote = [self.registers get:'"'];
    if (dquote.length) { [str appendFormat:@"\n\"\"   %@", dquote]; }
    // ':' command-line register holds the last executed ex command.
    NSString *cmd = [[VimbConfig shared].commandStore lines].firstObject ?: @"";
    if (cmd.length) { [str appendFormat:@"\n\":   %@", cmd]; }
    // Named registers 0-9, a-z, A-Z (only those that are filled).
    for (unichar c = '0'; c <= '9'; c++) {
        NSString *val = [self.registers get:c];
        if (val.length) { [str appendFormat:@"\n\"%C   %@", c, val]; }
    }
    for (unichar c = 'a'; c <= 'z'; c++) {
        NSString *val = [self.registers get:c];
        if (val.length) { [str appendFormat:@"\n\"%C   %@", c, val]; }
    }
    for (unichar c = 'A'; c <= 'Z'; c++) {
        NSString *val = [self.registers get:c];
        if (val.length) { [str appendFormat:@"\n\"%C   %@", c, val]; }
    }
    [self showMessage:str error:NO];
}

- (void)exSource:(NSString *)path {
    // :source [file] — default to the rc config file when no path given.
    NSString *file = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (file.length == 0) { file = [[VimbConfig shared] historyCommand]; }
    file = [file stringByExpandingTildeInPath];
    NSString *content = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        [self showMessage:[NSString stringWithFormat:@"cannot source %@", file] error:YES];
        return;
    }
    NSUInteger count = 0;
    for (NSString *raw in [content componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"\""] || [line hasPrefix:@"#"]) { continue; }
        [self.exEngine runCommand:line];
        count++;
    }
    [self showMessage:[NSString stringWithFormat:@"sourced %lu command%@ from %@",
                        (unsigned long)count, count == 1 ? @"" : @"s", file] error:NO];
}

- (void)exQueue:(NSString *)cmd arg:(NSString *)arg {
    VimbStorage *qs = [VimbConfig shared].queueStore;
    if ([cmd isEqualToString:@"qclear"]) {
        [qs clear];
        [self showMessage:@"queue cleared" error:NO];
        return;
    }
    if ([cmd isEqualToString:@"qpop"]) {
        NSString *url = [qs popLast];
        if (url.length == 0) {
            [self showMessage:@"queue is empty" error:YES];
            return;
        }
        // Load the front of the queue (and record it in history like :open).
        [self exOpen:url newTab:NO];
        return;
    }
    // GTK bookmark_queue_push appends to the END (util_file_append) while
    // qunshift prepends to the front (util_file_prepend); qpop pops the front.
    // That yields FIFO for qpush and LIFO-front for qunshift.
    NSString *url = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (url.length == 0) {
        [self showMessage:[cmd isEqualToString:@"qpush"] ? @"qpush requires a url" : @"qunshift requires a url" error:YES];
        return;
    }
    if ([cmd isEqualToString:@"qpush"]) {
        [qs append:url];
    } else { // qunshift
        [qs prepend:url max:NSUIntegerMax];
    }
    [self showMessage:[NSString stringWithFormat:@"queued %@", url] error:NO];
}
- (void)exShowMessages { [self showMessage:@"no messages" error:NO]; }

// Uniform async result channel (VimbExActor @optional). Async commands (eval,
// handler add/remove) report success/error here; KEEPINPUT is intentionally
// ignored for post-Enter async reports (the input box is already dismissed).
- (void)exReportResult:(VimbExCmdResult)result message:(nullable NSString *)message {
    if (!message.length) { return; }
    BOOL error = (result & VimbExCmdResultSuccess) == 0;
    [self showMessage:message error:error];
}

- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title {
    NSString *line = url;
    if (title.length) { line = [NSString stringWithFormat:@"%@ %@", url, title]; }
    [[VimbConfig shared].bookmarkStore prepend:line max:0];
    [self showMessage:[NSString stringWithFormat:@"added bookmark %@", url] error:NO];
}

- (void)exBookmarkCurrent:(NSString *)tags {
    // GTK :bma — always bookmarks the CURRENT page; the arg is tags only.
    NSString *uri = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString;
    if (!uri.length || [uri isEqualToString:@"about:blank"]) {
        [self showMessage:@"nothing to bookmark" error:YES];
        return;
    }
    NSString *title = self.activeTab.title.length ? self.activeTab.title : uri;
    NSString *line = uri;
    if (title.length) { line = [NSString stringWithFormat:@"%@ %@", uri, title]; }
    if (tags.length) { line = [line stringByAppendingFormat:@" %@", tags]; }
    [[VimbConfig shared].bookmarkStore prepend:line max:0];
    [self showMessage:[NSString stringWithFormat:@"added bookmark %@", uri] error:NO];
}

- (void)exUnbookmark:(NSString *)match {
    // GTK :bmr — exact strcmp on the URI; no arg removes the current page.
    NSString *target = match;
    if (!target.length) {
        target = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString;
    }
    if (!target.length) {
        [self showMessage:@"nothing to unbookmark" error:YES];
        return;
    }
    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    BOOL removed = NO;
    for (NSString *line in [[VimbConfig shared].bookmarkStore lines]) {
        NSString *url = [line componentsSeparatedByString:@" "].firstObject;
        if ([url isEqualToString:target]) { removed = YES; continue; }  // exact match
        [remaining addObject:line];
    }
    if (!removed) {
        [remaining removeObject:target];
    }
    [[VimbConfig shared].bookmarkStore writeAll:remaining];
    [self showMessage:removed ? @"bookmark removed" : @"no bookmark removed" error:!removed];
}

- (void)exNormal:(NSString *)keys applyMapping:(BOOL)applyMapping {
    // GTK ex_normal: enter normal mode then feed RHS keys; bang skips mapping.
    self.vim.mode = VimModeNormal;
    [self.vim reset];
    if (applyMapping) {
        for (NSUInteger i = 0; i < keys.length; i++) {
            unichar c = [keys characterAtIndex:i];
            [self.vim handleKeyCode:0 modifiers:0 characters:[NSString stringWithCharacters:&c length:1]];
        }
    } else {
        [self.vim feedParserString:keys];
    }
}

- (void)exHandlerAdd:(NSString *)scheme command:(NSString *)command success:(void (^)(BOOL))callback {
    BOOL ok = [[VimbConfig shared].handler addScheme:scheme command:command];
    if (ok) {
        [self showMessage:[NSString stringWithFormat:@"handler %@ -> %@", scheme, command] error:NO];
    }
    if (callback) { callback(ok); }
}

- (void)exHandlerRemove:(NSString *)scheme success:(void (^)(BOOL))callback {
    BOOL ok = [[VimbConfig shared].handler removeScheme:scheme];
    if (ok) { [self showMessage:[NSString stringWithFormat:@"handler %@ removed", scheme] error:NO]; }
    if (callback) { callback(ok); }
}

// :bookmarks — present the bookmark browser panel (parity with src/bookmark.c's
// gB-style browse flow).
- (void)exShowBookmarks {
    [[VimbBookmarkBrowser sharedBrowser] presentBookmarks];
}

// Menu-bar / keyboard shortcut entry point (File ▸ Bookmarks).
- (IBAction)showBookmarks:(id)sender {
    (void)sender;
    [[VimbBookmarkBrowser sharedBrowser] presentBookmarks];
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
    // The docked status line is always visible, so a message just replaces
    // the URL text and restores it (or the next message) after a pause.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.statusField.stringValue isEqualToString:message]) {
            [self updateStatus];
        }
    });
}

- (BOOL)inputAutohide {
    return [[VimbConfig shared] getBool:@"input-autohide" defaultValue:YES];
}

- (void)showCommandLine {
    // Reveal the docked input row (input-autohide collapses it while idle),
    // then focus the field immediately (not after any animation) so the first
    // keystroke lands in the command line and not the webview, and put the
    // caret after any seeded prompt (":", "/", "?").
    self.commandField.hidden = NO;
    self.inputRowHeight.constant = 26;
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window makeFirstResponder:self.commandField];
    NSText *editor = [self.commandField currentEditor];
    if (editor) {
        [editor setSelectedRange:NSMakeRange(editor.string.length, 0)];
    }
}

- (void)hideCommandLine {
    [self.completionDropdown dismiss];
    // Clear through the field editor when it is active: assigning stringValue
    // alone is ignored while editing, so the stale editor text reappeared and
    // appended to the next session's keystrokes.
    NSText *editor = [self.commandField currentEditor];
    if (editor) { editor.string = @""; }
    self.commandField.stringValue = @"";
    if ([self inputAutohide]) {
        self.inputRowHeight.constant = 0;
        self.commandField.hidden = YES;
    }
    if (self.activeTab) { [self.window makeFirstResponder:self.activeTab.view]; }
}

- (void)updateStatus {
    if (!self.activeTab) { return; }
    NSString *url = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString ?: @"";
    // The docked status line is always visible (GTK parity: the status bar
    // persistently shows the URI); no hide/flash logic needed.
    self.statusField.stringValue = url;
    [self updateSettingsIndicator];
}

// status-bar-show-settings: render the STATUS_VARAIBLE_SHOW token (parity with
// src/main.c). Entries follow src/config.def.h; no incognito mode here so the
// 'E/e' slot stays lowercase like the default non-incognito state.
- (void)updateSettingsIndicator {
    VimbConfig *cfg = [VimbConfig shared];
    BOOL show = [cfg getBool:@"status-bar-show-settings" defaultValue:NO];
    self.settingsIndicator.hidden = !show;
    if (!show) { self.settingsIndicator.stringValue = @""; return; }
    NSString *cookie = [cfg getString:@"cookie-accept" defaultValue:@"always"];
    unichar ck = [cookie isEqualToString:@"always"] ? 'A' : ([cookie isEqualToString:@"origin"] ? '@' : 'a');
    unichar tk[8];
    tk[0] = ck;
    tk[1] = [cfg getBool:@"dark-mode" defaultValue:NO] ? 'D' : 'd';
    tk[2] = 'e'; // no incognito -> default non-incognito
    tk[3] = [cfg getBool:@"images" defaultValue:YES] ? 'I' : 'i';
    tk[4] = [cfg getBool:@"html5-local-storage" defaultValue:YES] ? 'L' : 'l';
    tk[5] = [cfg getBool:@"stylesheet" defaultValue:YES] ? 'M' : 'm';
    tk[6] = [cfg getBool:@"scripts" defaultValue:YES] ? 'S' : 's';
    tk[7] = [cfg getBool:@"strict-ssl" defaultValue:YES] ? 'T' : 't';
    self.settingsIndicator.stringValue = [NSString stringWithCharacters:tk length:8];
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
    } else if ([t isEqualToString:@"hintdata"]) {
        [self handleHintData:payload];
    } else if ([t isEqualToString:@"hintyank"]) {
        // Kept for compatibility with older hint scripts; routed identically to
        // a data-mode yank (into ';' then the default register).
        NSString *url = payload[@"url"] ?: @"";
        [self yankPromptValue:url];
        [self exitHintMode];
    } else if ([t isEqualToString:@"hintopen"]) {
        NSString *url = payload[@"url"] ?: @"";
        if (url.length) {
            [self loadURL:url inNewTab:YES];
            [self showMessage:[NSString stringWithFormat:@"opened in new tab %@", url] error:NO];
        }
        [self exitHintMode];
    }
}

#pragma mark - Helpers

// 1px hairline pinned to a bar's top edge; NSBox uses the system separator
// color so it adapts to light/dark (HIG separators are hairline, not 2pt).
// Call after the box has a superview: [bar addSubview:[self hairline]].
- (NSBox *)hairlineSeparator {
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    return sep;
}

- (VimbTab *)tabForWebView:(KeyboardWebView *)view {
    for (VimbTab *t in self.tabs) {
        if (t.webView == view) { return t; }
    }
    return nil;
}

#pragma mark - Hint actions

// Handles the unified {t:'hintdata', mode, value, action} message produced by
// the hint overlay. This is the native port of hint_function_check_result's
// "DATA:"/"DONE:"/"INSERT:" handling.
- (void)handleHintData:(NSDictionary *)payload {
    NSString *modeStr = payload[@"mode"] ?: @"";
    NSString *value = payload[@"value"] ?: @"";
    NSString *action = payload[@"action"] ?: @"DATA";
    unichar mode = modeStr.length ? [modeStr characterAtIndex:0] : 0;
    BOOL gmode = self.currentHintGmode;
    VimbHintDispatch dispatch = VimbHintDispatchNone;

    if ([action isEqualToString:@"DATA"]) {
        // Put the hinted value into the ';' register first (port of
        // vb_register_add(c, ';', v) in hint_function_check_result).
        [self.registers set:value forKey:';'];
        dispatch = [VimbHintEngine dispatchForDataMode:mode];
        switch (dispatch) {
            case VimbHintDispatchOpen: {
                // i/I: open the image url (I -> new tab).
                BOOL newTab = [VimbHintEngine opensNewTab:mode];
                [self loadURL:value inNewTab:newTab];
                if (!newTab) { [self recordHistory:value]; }
                [self showMessage:[NSString stringWithFormat:@"open %@%@", newTab ? @"in new tab " : @"", value] error:NO];
                break;
            }
            case VimbHintDispatchCommandOpen: {
                // O/T: prefill the command line (":open <url>" / ":tabopen <url>").
                NSString *prefix = (mode == 'T') ? @"tabopen " : @"open ";
                NSString *prompt = [NSString stringWithFormat:@"%@%@", prefix, value];
                if (gmode) {
                    // g-mode echoes but stays hinting (mirrors vb_echo without
                    // entering command mode).
                    [self showMessage:prompt error:NO];
                } else {
                    self.vim.mode = VimModeCommand;
                    [self vimOpenPrompt:prompt mode:VimModeCommand];
                }
                break;
            }
            case VimbHintDispatchSave:
                [self saveURI:value path:nil];
                break;
            case VimbHintDispatchXHint:
                [self runXHintCommandWithValue:value];
                break;
            case VimbHintDispatchYank:
                [self yankPromptValue:value];
                break;
            case VimbHintDispatchQueue: {
                // p/P: push/unshift onto the read-later queue. vimb's storage
                // only keeps front/front ordering, so both use prepend (the
                // unshift distinction is preserved for the caller).
                BOOL unshift = (mode == 'P');
                [[VimbConfig shared].queueStore prepend:value max:NSUIntegerMax];
                [self showMessage:[NSString stringWithFormat:@"queued %@", value] error:NO];
                (void)unshift;
                break;
            }
            case VimbHintDispatchRemove:   // k: element already removed by the script
            case VimbHintDispatchInsert:   // e with INSERT handled below
            case VimbHintDispatchNone:
            default:
                break;
        }
    } else if ([action isEqualToString:@"INSERT"]) {
        // The script focused a form field. For 'e' we seed the ';' register
        // with the field value and auto-open the editor (GTK hints.c:385-387
        // input_open_editor on the ';e' hint mode INSERT result).
        if (mode == 'e') {
            [self.registers set:value forKey:';'];
            [self vimOpenEditor];
        }
    }

    // Leave hint mode unless g-mode keeps it open, or we transitioned into
    // command mode to edit a prefilled open prompt (O/T, non-g-mode).
    BOOL toCommand = ([action isEqualToString:@"DATA"] && dispatch == VimbHintDispatchCommandOpen && !gmode);
    if (!gmode && !toCommand) {
        [self exitHintMode];
    }
    // gmode (or toCommand) intentionally keeps hint/command mode active.
}

// Runs the x-hint-command setting with <C-R>; replaced by the hinted value
// (port of map_handle_string(c, GET_CHAR("x-hint-command"), true) — the value
// is already in the ';' register).
- (void)runXHintCommandWithValue:(NSString *)value {
    NSString *tmpl = [[VimbConfig shared] getString:@"x-hint-command" defaultValue:@":o <C-R>;"] ?: @":o <C-R>;";
    NSString *line = [tmpl stringByReplacingOccurrencesOfString:@"<C-R>;" withString:value ?: @""];
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([line hasPrefix:@":"]) { line = [line substringFromIndex:1]; }
    if (line.length) { [self.exEngine runCommand:line]; }
}

// Puts `value` into the default register, the pasteboard and the ';' register
// (mirrors the 'y'/'Y' hint action's command_yank into the current register).
- (void)yankPromptValue:(NSString *)value {
    [self.registers set:value forKey:';'];
    [self.registers set:value forKey:'"'];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:value forType:NSPasteboardTypeString];
    [self showMessage:[NSString stringWithFormat:@"yanked %@", value] error:NO];
}

// Exits hint mode: resets the vim engine to normal and returns focus to the
// webview. The overlay is already torn down by the script for non-g-mode, but
// we clear defensively so the hint state can never stay resident.
- (void)exitHintMode {
    [self.vim reset];
    [self.activeTab.webView toggleHints:nil];
    if (self.activeTab) { [self.window makeFirstResponder:self.activeTab.view]; }
}

- (void)vimOpenPrompt:(NSString *)prompt mode:(VimMode)mode {
    if (mode == VimModeHint) {
        // Hint mode keeps the webview focused so hint keys route to JS.
        [self hideCommandLine];
        return;
    }
    self.commandPrefix = prompt;
    self.exHistorySnapshot = @[];
    self.exHistoryIndex = -1;
    // Seed the prompt character (":", "/", "?") into the field for parity with
    // GTK vb_enter_prompt(print_prompt=TRUE). "open "/"tabopen " (o/O/t/T) and
    // ";" hint prompts prefill their full command text instead. Keeping the
    // prompt in the field makes incsearch + completion (which key off the
    // leading char) work and restores the visual cue of forward vs. backward
    // search vs. ex-command.
    // Seed the prompt through the field editor when one is live (a stale
    // editor ignores stringValue and would resurrect its old text).
    NSString *seed = @"";
    if ([prompt hasPrefix:@"open "] || [prompt hasPrefix:@"tabopen "]) {
        seed = prompt;
    } else if (prompt.length == 1 &&
               ([prompt isEqualToString:@":"] || [prompt isEqualToString:@"/"] || [prompt isEqualToString:@"?"])) {
        seed = prompt;
    }
    NSText *seedEditor = [self.commandField currentEditor];
    if (seedEditor) { seedEditor.string = seed; }
    self.commandField.stringValue = seed;
    self.commandField.placeholderString = [prompt isEqualToString:@":"] ? @"command" : @"search";
    [self showCommandLine];
}

#pragma mark - VimDelegate

// Mirrors vimb's normal_scroll -> vbscroll() dispatch (src/scripts/scroll.js).
- (void)vimScrollMode:(unichar)mode count:(NSUInteger)count {
    if (count == 0) { count = 1; }
    CGFloat step = [[VimbConfig shared] scrollStep];
    switch (mode) {
        case 'j': [self.activeTab.webView scrollBy:0 y:(step * count)]; break;
        case 'k': [self.activeTab.webView scrollBy:0 y:-(step * count)]; break;
        case 'h': [self.activeTab.webView scrollBy:-(step * count) y:0]; break;
        case 'l': [self.activeTab.webView scrollBy:(step * count) y:0]; break;
        case 0x14: /* ^P unused here */ [self.activeTab.webView scrollBy:0 y:(step * count)]; break;
        case 0x06: /* ^F */ [self pagedScrollDown:count]; break;
        case 0x02: /* ^B */ [self pagedScrollUp:count]; break;
        case 0x15: /* ^U */ [self pagedScrollHalfUp:count]; break;
        case 0x04: /* ^D */ [self pagedScrollHalfDown:count]; break;
        case 'G':
            if (count >= 1) {
                // NG: scroll to N% (100 -> bottom), matching scroll.js 'G'/'g'.
                [self.activeTab.webView scrollToPercent:(count >= 100 ? 100 : count)];
            } else {
                [self.activeTab.webView scrollToBottom];
            }
            break;
        case 'g':
            if (count >= 1) {
                // Ngg: scroll to N% (100 -> bottom).
                [self.activeTab.webView scrollToPercent:(count >= 100 ? 100 : count)];
            } else {
                [self.activeTab.webView scrollToTop];
            }
            break;
        case '0': [self.activeTab.webView scrollToX:0]; break;
        case '$': [self.activeTab.webView scrollToXEnd]; break;
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
- (void)vimReloadBypassCache {
    // R: reload bypassing the HTTP cache (GTK webkit_web_view_reload_bypass_cache).
    [self.activeTab.webView reloadFromOrigin:nil];
}
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

- (void)vimOpenHomePage:(BOOL)newTab {
    // gh / gH: navigate to the configured home-page (current / new tab).
    NSString *start = [[VimbConfig shared].settings objectForKey:@"home-page"];
    if (![start isKindOfClass:[NSString class]] || !start.length) { start = @"about:blank"; }
    [self loadURL:start inNewTab:newTab];
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
    [self.commandField.animator setAlphaValue:0.0];
    [self.activeTab.webView findString:query forwardDirection:forward];
    [self showMessage:[NSString stringWithFormat:@"Search: %@", query] error:NO];
}
- (void)vimSearchDirection:(NSInteger)dir {
    // dir is a signed count: sign = direction, magnitude = repeat count.
    KeyboardWebView *wv = self.activeTab.webView;
    BOOL forward = (dir >= 0);
    NSInteger n = labs(dir);
    if (n < 0) { n = 1; }
    for (NSInteger i = 0; i < n; i++) {
        [wv findNextDirection:forward];
    }
}
- (void)vimSearchSelectionForward:(BOOL)forward {
    // #/* search the current page selection (port of normal_search_selection).
    __weak typeof(self) weakSelf = self;
    [self.activeTab.webView evaluateJavaScript:
        @"(window.getSelection&&window.getSelection().toString?window.getSelection().toString():'')"
        completionHandler:^(id result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || ![result isKindOfClass:[NSString class]]) {
                    [weakSelf showMessage:@"no selection to search" error:YES];
                    return;
                }
                NSString *sel = [(NSString *)result stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (sel.length == 0) {
                    [weakSelf showMessage:@"no selection to search" error:NO];
                    return;
                }
                [weakSelf.activeTab.webView findString:sel forwardDirection:forward];
                [weakSelf showMessage:[NSString stringWithFormat:@"Search: %@", sel] error:NO];
            });
        }];
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
    self.vim.mode = VimModePassThrough;
    [self showMessage:@"-- PASS THROUGH -- (Press ESC to return)" error:NO];
    // Focus the web view so page keys are received.
    [self.window makeFirstResponder:self.activeTab.view];
}
- (void)vimViewSource {
    NSString *uri = self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString ?: @"";
    NSURL *url = [NSURL URLWithString:uri];
    if (!url) { [self showMessage:@"cannot view source" error:YES]; return; }
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        (void)resp;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                [weakSelf showMessage:[@"view source failed: " stringByAppendingString:err ? err.localizedDescription : @""] error:YES];
                return;
            }
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [NSString stringWithFormat:@"%lu bytes (non-UTF8)", (unsigned long)data.length];
            NSString *escaped = [self escapeHTML:html];
            NSString *display = [NSString stringWithFormat:
                @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
                @"<title>view-source:%@</title><style>"
                @"body{font:12px Menlo,monospace;white-space:pre-wrap;word-wrap:break-word;"
                @"padding:16px;margin:0;}</style></head><body>%@</body></html>",
                uri, escaped];
            [weakSelf openViewSourceTabWithHTML:display];
        });
    }] resume];
}

- (void)openViewSourceTabWithHTML:(NSString *)html {
    [self newTabInWindow];
    [self.activeTab.webView loadHTMLString:html baseURL:nil];
}

// gF: open an in-app DOM inspector for the current page (GTK
// normal_view_inspector). WKWebView exposes no public API to open its native
// WebKit inspector programmatically, so this renders a collapsed DOM tree in a
// new tab, gated on the webinspector setting like GTK's developer-extras.
- (void)vimViewInspector {
    if (![[VimbConfig shared] getBool:@"webinspector" defaultValue:NO]) {
        [self showMessage:@"webinspector is not enabled" error:YES];
        return;
    }
    WKWebView *wv = self.activeTab.webView;
    if (!wv.URL) { [self showMessage:@"cannot inspect: no page loaded" error:YES]; return; }
    __weak typeof(self) weakSelf = self;
    // Serialize a focused DOM tree (tag, id/class, text, href) capped by node
    // count/depth to stay fast on large pages. Returns a full HTML document.
    NSString *js =
    @"(function(){"
    "  const CAP=400, DEPTH=8;"
    "  const esc=s=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;');"
    "  let n=0, html='<ul>';"
    "  function walk(el,d){"
    "    for(const child of el.children){"
    "      if(child.nodeType!==1){continue;}"
    "      if(++n>CAP||d>DEPTH){html+='<li>…</li>';continue;}"
    "      const tag=child.tagName.toLowerCase();"
    "      let label='<'+tag;"
    "      if(child.id)label+=' id=\"'+child.id+'\"';"
    "      if(child.className&&typeof child.className==='string')label+=' class=\"'+child.className+'\"';"
    "      label+='>';"
    "      let txt='';"
    "      if(child.children.length===0){ const t=(child.textContent||'').trim(); txt=t?esc(t.slice(0,80)):''; }"
    "      if(child.href)label+=' href=\"'+child.href+'\"';"
    "      html+='<li><details'+(d<2?' open':'')+'><summary>'+esc(label)+(txt?' '+txt:'')+'</summary>';"
    "      if(child.children.length){html+='<ul>';walk(child,d+1);html+='</ul>';}"
    "      html+='</details></li>';"
    "    }"
    "  }"
    "  walk(document.documentElement||document.body,0);"
    "  html+='</ul>';"
    "  return '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>vimb DOM inspector</title><style>"
    "    body{font:12px Menlo,monospace;margin:16px;background:#fff;color:#111;}"
    "    ul{list-style:none;padding-left:14px;} summary{cursor:pointer;}"
    "    summary:hover{background:#eee;}</style></head><body>"
    "    <p><b>vimb DOM inspector</b> — <a href=\"#\" onclick=\"return false;\">back</a> (400-node cap)</p>"
    "    '+html+'</body></html>';"
    "})()";
    [wv evaluateJavaScript:js completionHandler:^(id result, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || ![result isKindOfClass:[NSString class]]) {
                [weakSelf showMessage:@"inspector failed to read the DOM" error:YES];
                return;
            }
            [weakSelf openViewSourceTabWithHTML:(NSString *)result];
        });
    }];
}

- (NSString *)escapeHTML:(NSString *)s {
    NSMutableString *out = [s mutableCopy];
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

- (void)vimOpenEditor {
    // Ctrl-T / ;e: edit the focused text field with the external editor.
    NSString *cmd = [[VimbConfig shared] getString:@"editor-command" defaultValue:@"/usr/bin/open -t '%s'"];
    if (cmd.length == 0) { [self showMessage:@"no editor-command configured" error:YES]; return; }
    __weak typeof(self) weakSelf = self;
    [self.activeTab.webView evaluateJavaScript:
        @"(window.vimb_input_mode_element && window.vimb_input_mode_element.value) ? "
        @"window.vimb_input_mode_element.value : ''"
        completionHandler:^(id result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) { [weakSelf showMessage:@"could not read field" error:YES]; return; }
                NSString *initial = ([result isKindOfClass:[NSString class]] ? result : @"");
                VimbEditor *ed = [[VimbEditor alloc] init];
                BOOL ok = [ed editText:initial editorCommand:cmd completion:^(NSString *edited, NSString *path) {
                    (void)path;
                    if (edited == nil) { edited = @""; }
                    // Write the edited text back to the focused field.
                    NSString *escaped = [edited stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
                    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
                    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
                    NSString *js = [NSString stringWithFormat:
                        @"if(window.vimb_input_mode_element){window.vimb_input_mode_element.value='%@';}",
                        escaped];
                    [weakSelf.activeTab.webView evaluateJavaScript:js completionHandler:nil];
                    [weakSelf showMessage:@"edited" error:NO];
                }];
                if (!ok) { [weakSelf showMessage:@"editor failed to launch" error:YES]; }
            });
        }];
}

- (void)vimYankURI:(unichar)reg {
    NSString *url = self.activeTab.url.absoluteString ?: @"";
    [self.registers set:url forKey:reg];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:url forType:NSPasteboardTypeString];
    [self showMessage:[NSString stringWithFormat:@"yanked %@", url] error:NO];
}

- (NSString *)vimCurrentURI {
    return self.activeTab.url.absoluteString ?: self.activeTab.webView.URL.absoluteString ?: @"";
}

- (void)vimYankSelection:(unichar)reg {
    // Y: yank the current page selection into the register (command_yank
    // COMMAND_YANK_SELECTION).
    __weak typeof(self) weakSelf = self;
    [self.activeTab.webView evaluateJavaScript:
        @"(window.getSelection&&window.getSelection().toString?window.getSelection().toString():'')"
        completionHandler:^(id result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || ![result isKindOfClass:[NSString class]]) {
                    [weakSelf showMessage:@"no selection to yank" error:YES];
                    return;
                }
                NSString *sel = result;
                if (sel.length == 0) {
                    [weakSelf showMessage:@"no selection to yank" error:NO];
                    return;
                }
                [weakSelf.registers set:sel forKey:reg];
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:sel forType:NSPasteboardTypeString];
                [weakSelf showMessage:[NSString stringWithFormat:@"yanked %@", sel] error:NO];
            });
        }];
}

- (void)vimSetMark:(unichar)c {
    VimbMarks *marks = self.marks;
    KeyboardWebView *wv = self.activeTab.webView;
    NSString *curUri = self.activeTab.url.absoluteString ?: wv.URL.absoluteString ?: @"";
    NSString *key = [NSString stringWithCharacters:&c length:1];
    if (isupper(c)) {
        [wv getScrollTopWithCompletion:^(double top) {
            [marks setGlobal:c uri:curUri];
            self.pendingMarkY[key] = @(top);
            [self showMessage:[NSString stringWithFormat:@"mark %@: %@", key, curUri] error:NO];
        }];
    } else {
        [wv getScrollTopWithCompletion:^(double top) {
            [marks setLocal:c top:top];
            [self showMessage:[NSString stringWithFormat:@"mark %@ set at y=%.0f", key, top] error:NO];
        }];
    }
}

- (void)vimJumpMark:(unichar)c {
    VimbMarks *marks = self.marks;
    KeyboardWebView *wv = self.activeTab.webView;
    BOOL isGlobal = isupper(c);
    if (isGlobal) {
        NSString *uri = [marks getGlobal:c];
        if (!uri) { [self showMessage:@"mark not set" error:NO]; return; }
        NSNumber *pos = self.pendingMarkY[[NSString stringWithCharacters:&c length:1]];
        [wv jumpToURI:uri withY:pos ? pos.doubleValue : 0];
    } else {
        double top = [marks getLocal:c];
        [wv scrollToY:top];
    }
}
- (void)vimQueuePop {
    [self exQueue:@"qpop" arg:@""];
}

- (void)vimZoomKey:(unichar)key count:(NSInteger)count {
    if (count < 1) { count = 1; }
    if (key == 'z') {
        // zz: reset to default zoom.
        self.activeTab.webView.magnification = [[VimbConfig shared] getInt:@"default-zoom" defaultValue:100] / 100.0;
        return;
    }
    CGFloat f = self.activeTab.webView.magnification;
    if (key == 'i' || key == 'I') {
        f += (CGFloat)count * 0.1;
    } else { // 'o' / 'O': zoom out
        f = MAX(0.5, f - (CGFloat)count * 0.1);
    }
    self.activeTab.webView.magnification = f;
}
- (void)vimIncrement:(BOOL)up count:(NSInteger)count {
    NSInteger delta = up ? count : -count;
    if (count == 0) { delta = up ? 1 : -1; }
    [self.activeTab.webView incrementURI:delta];
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
- (void)vimEnterHints:(NSString *)mode gmode:(BOOL)gmode {
    self.currentHintGmode = gmode;
    [self.activeTab.webView toggleHints:mode gmode:gmode];
}
- (void)vimHintKey:(NSString *)key { [self.activeTab.webView sendHintKey:key]; }
- (void)vimHintFocus:(BOOL)back { [self.activeTab.webView hintFocus:back]; }
- (void)vimHintBackspace { [self.activeTab.webView hintBackspace]; }
- (void)vimHintFire { [self.activeTab.webView hintFire]; }
- (void)vimShowMessage:(NSString *)message error:(BOOL)error { [self showMessage:message error:error]; }
- (void)vimFocusWebView {
    [self hideCommandLine];
}

#pragma mark - Command field (NSTextFieldDelegate)

- (void)controlTextDidChange:(NSNotification *)obj {
    NSString *line = self.commandField.stringValue;

    // GTK parity (ex.c ex_keypress check_empty): deleting back past the prompt
    // char empties the input and returns to normal mode, like vim.
    if (line.length == 0) {
        [self.vim reset];
        [self hideCommandLine];
        return;
    }

    // GTK parity (main.c on_textbuffer_changed): while a completion session is
    // active, text edits do NOT re-run any changed handler — backspace just
    // edits the buffer (the completion stays put; the next Tab restarts it
    // because the input no longer matches the applied selection).
    if (self.completionDropdown.hasCandidates) { return; }

    // Incremental search (vim's 'incsearch'): while the user types a / or ?
    // search, highlight matches live instead of waiting for Enter. Finding on
    // an empty query would just clear the previous highlight, so skip it.
    if (self.vim.mode == VimModeSearch && [[VimbConfig shared] incsearch]) {
        if (line.length > 1) {
            unichar p = [line characterAtIndex:0];
            if (p == '/' || p == '?') {
                NSString *query = [line substringFromIndex:1];
                if (query.length > 0) {
                    [self.activeTab.webView findString:query forwardDirection:(p == '/')];
                }
            }
        }
    }
}
- (void)controlTextDidEndEditing:(NSNotification *)obj { }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.commandField) {
        // Enter applies the highlighted candidate, Esc dismisses; Tab and
        // Shift-Tab always go through completeCommandFieldDirection: which
        // steps an active session (input still matches the applied selection)
        // or (re)builds it — GTK ex.c complete().
        if ((commandSelector == @selector(insertNewline:)) && self.completionDropdown.hasCandidates
            && self.completionDropdown.selectedValue.length > 0) {
            NSString *choice = self.completionDropdown.selectedValue;
            [self.completionDropdown dismiss];
            [self commandLineCommittedWithCompletion:choice];
            return YES;
        }
        if ((commandSelector == @selector(cancelOperation:)) && self.completionDropdown.hasCandidates) {
            [self.completionDropdown dismiss];
            return YES;
        }
        if (commandSelector == @selector(insertNewline:)) {
            NSString *line = self.commandField.stringValue;
            VimMode m = self.vim.mode;
            [self.completionDropdown dismiss];
            // Route both command (":") and search ("/", "?") lines through the
            // same executor so search also records history and strips its
            // leading prompt char (parity with GTK ex_input / command_search).
            VimbExCmdResult res = [self commandLineExecuted:line];
            [self.vim reset];
            if ((res & VimbExCmdResultKeepInput) && m == VimModeCommand) {
                // GTK CMD_KEEPINPUT: keep the typed command in the input box
                // (still focused) so it can be corrected/continued.
                [self.window makeFirstResponder:self.commandField];
            } else {
                [self hideCommandLine];
            }
            return YES;
        }
        if (commandSelector == @selector(cancelOperation:)) {
            [self.vim reset];
            [self hideCommandLine];
            return YES;
        }
        if (commandSelector == @selector(insertTab:)) {
            [self completeCommandField];
            return YES;
        }
        if (commandSelector == @selector(insertBacktab:)) {
            [self completeCommandFieldDirection:-1];
            return YES;
        }
        // Arrow Up/Down while editing arrive as moveUp:/moveDown: on the
        // field editor (not keyDown:). GTK main.c maps GDK Up/Down to
        // ex_keypress KEY_UP/KEY_DOWN -> history(); with an open completion
        // they step the highlighted candidate instead (requestedHistory:
        // dispatches on completionDropdown.hasCandidates).
        if (commandSelector == @selector(moveUp:)) {
            [self commandField:self.commandField requestedHistory:-1];
            return YES;
        }
        if (commandSelector == @selector(moveDown:)) {
            [self commandField:self.commandField requestedHistory:1];
            return YES;
        }
    }
    return NO;
}

#pragma mark - VimbCommandFieldDelegate

- (void)commandFieldRequestedCancel:(VimbCommandField *)field {
    [self.vim reset];
    [self hideCommandLine];
}

- (nullable NSString *)commandField:(VimbCommandField *)field registerContentForKey:(unichar)key {
    NSString *v = [self.registers get:key];
    if (v) { return v; }
    // Fall back to the default register (").
    if (key == '"') { return [self.registers get:'"']; }
    return nil;
}

- (void)commandFieldDeleteWord:(VimbCommandField *)field {
    // Delete the word before the cursor.
    NSText *editor = [field currentEditor];
    if (editor && editor.selectedRange.location != NSNotFound) {
        NSUInteger loc = editor.selectedRange.location;
        NSString *s = editor.string;
        NSUInteger start = loc;
        while (start > 0) {
            unichar c = [s characterAtIndex:start - 1];
            if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) { break; }
            start--;
        }
        // consume preceding whitespace too
        while (start > 0) {
            unichar c = [s characterAtIndex:start - 1];
            if (![[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) { break; }
            start--;
        }
        [editor replaceCharactersInRange:NSMakeRange(start, loc - start) withString:@""];
    }
}

- (void)commandField:(VimbCommandField *)field requestedHistory:(NSInteger)direction {
    // While a completion session is active, Up/Down step the highlighted
    // candidate (parity with the GTK completion list keeping keyboard focus
    // in the list; main.c routes Up/Down to ex_keypress only when no
    // completion holds the focus).
    if (self.completionDropdown.hasCandidates) {
        [self stepDropdownSelectionBy:direction];
        return;
    }
    VimMode m = self.vim.mode;
    if (m != VimModeCommand && m != VimModeSearch) { return; }
    VimbStorage *store = [VimbConfig shared].commandStore;
    if (m == VimModeSearch) { store = [VimbConfig shared].searchStore; }
    NSArray<NSString *> *hist = [store lines];
    if (hist.count == 0) { return; }
    if (self.exHistorySnapshot.count == 0) {
        self.exHistorySnapshot = hist;
    }
    self.exHistoryIndex += (direction < 0 ? 1 : -1);
    if (self.exHistoryIndex < 0) { self.exHistoryIndex = 0; }
    if (self.exHistoryIndex >= (NSInteger)hist.count) { self.exHistoryIndex = (NSInteger)hist.count - 1; }
    NSString *line = hist[self.exHistoryIndex];
    // History entries are stored WITHOUT their prompt char (command history
    // drops ":", search history drops "/"/"?"), but the live field carries the
    // seeded prompt. Re-apply it so the recalled line routes correctly.
    if (m == VimModeSearch) {
        NSString *p = self.commandPrefix.length == 1 ? self.commandPrefix : @"/";
        if (![line hasPrefix:p]) { line = [p stringByAppendingString:line]; }
    } else if (![line hasPrefix:@":"]) {
        line = [@":" stringByAppendingString:line];
    }
    // Write through the editor for the same reason as everywhere else:
    // an active editor ignores a stringValue assignment.
    NSText *histEditor = [self.commandField currentEditor];
    if (histEditor) { histEditor.string = line; }
    self.commandField.stringValue = line;
}

// Tab completion for the command line, mirroring ex.c's complete(). Tab
// completes and steps forward, Shift+Tab steps backward. Completes: command
// names, :open/:tabopen URLs (history+bookmarks+closed), :set names,
// :bma/:bmr bookmarks, and /-? search history.
- (void)completeCommandField { [self completeCommandFieldDirection:1]; }

// Strip leading ':' and whitespace the way GTK complete() does before
// matching, so ":open ex" completes exactly like "open ex" (the seeded ':'
// prompt char stays in the field but must not break prefix matching).
- (NSString *)completionNormalizedLine:(NSString *)line {
    return [CompletionMatcher normalizedLine:line];
}

// The fixed part of the line before the token being completed: the prompt
// char plus any command word — ":", ":open ", "/", ":set ". Rewriting the
// field as "head + candidate" keeps everything the user already typed.
- (NSString *)completionHeadForLine:(NSString *)line {
    return [CompletionMatcher completionHeadForLine:line];
}

// Collect ordered completion candidate strings for a command/search line,
// without applying anything. Reused by the Tab-cycling path and the live
// completion dropdown (parity with src/completion.c candidate generation).
// GTK g_str_has_prefix parity: the empty prefix matches everything
// (NSString hasPrefix:@"" returns NO on this toolchain, which broke ":open "
// + Tab / "/" + Tab listing all candidates).
static BOOL vbHasPrefix(NSString *s, NSString *prefix) {
    return prefix.length == 0 || [s hasPrefix:prefix];
}

- (NSArray<NSString *> *)completionCandidatesForLine:(NSString *)line {
    NSMutableArray<NSString *> *cands = [NSMutableArray array];

    if ([line hasPrefix:@"/"] || [line hasPrefix:@"?"]) {
        NSString *prefix = [line substringFromIndex:1];
        for (NSString *h in [[VimbConfig shared].searchStore lines]) {
            if (vbHasPrefix(h, prefix) && ![cands containsObject:h]) { [cands addObject:h]; }
        }
        return cands;
    }

    // Command matching happens on the ':'-stripped line (GTK parity).
    NSString *norm = [self completionNormalizedLine:line];

    if ([norm hasPrefix:@"open "] || [norm hasPrefix:@"tabopen "]) {
        BOOL tab = [norm hasPrefix:@"tabopen "];
        NSString *prefix = [norm substringFromIndex:(tab ? 8 : 5)];
        BOOL book = [prefix hasPrefix:@"!"];
        if (book) { prefix = [prefix substringFromIndex:1]; }
        for (NSDictionary *b in [self bookmarksByPrefix:prefix]) { if (book || vbHasPrefix(b[@"url"], prefix)) [cands addObject:b[@"url"]]; }
        if (!book) {
            for (NSString *h in [[VimbConfig shared].historyStore lines]) { if (vbHasPrefix(h, prefix) && ![cands containsObject:h]) [cands addObject:h]; }
            for (NSString *c in [[VimbConfig shared].closedStore lines]) { if (vbHasPrefix(c, prefix) && ![cands containsObject:c]) [cands addObject:c]; }
        }
        return cands;
    }

    if ([norm hasPrefix:@"set "]) {
        NSString *prefix = [norm substringFromIndex:4];
        for (NSString *name in [VimbConfig shared].settings.allKeys) {
            if (vbHasPrefix(name, prefix)) { [cands addObject:name]; }
        }
        return cands;
    }

    if ([norm hasPrefix:@"bma "] || [norm hasPrefix:@"bmr "]) {
        NSString *prefix = [norm containsString:@" "] ? [norm substringFromIndex:([norm rangeOfString:@" "].location + 1)] : @"";
        for (NSDictionary *b in [self bookmarksByPrefix:prefix]) { [cands addObject:b[@"url"]]; }
        return cands;
    }

    if ([norm hasPrefix:@"bdelete "] || [norm hasPrefix:@"bd "] || [norm hasPrefix:@"b "]) {
        NSString *prefix = [norm containsString:@" "] ? [norm substringFromIndex:([norm rangeOfString:@" "].location + 1)] : @"";
        for (VimbTab *t in self.tabs) {
            NSString *turl = t.url.absoluteString ?: t.webView.URL.absoluteString ?: @"";
            NSString *ttitle = t.title ?: @"";
            if ([turl hasPrefix:prefix] || [ttitle hasPrefix:prefix]) { [cands addObject:turl]; }
        }
        return cands;
    }

    // Bare command name completion.
    if (![norm containsString:@" "]) {
        for (NSString *name in self.exEngine.commandNames) {
            if (vbHasPrefix(name, norm)) { [cands addObject:name]; }
        }
    }
    return cands;
}

// Rewrite the command field from the completion itself (selection sync via
// onSelectionChanged / stepDropdownSelectionBy:). controlTextDidChange does no
// completion work, so no feedback loop can arise; the caret moves to the end
// like GTK's completion_select writing the full line.
- (void)setCommandFieldTextSuppressingCompletion:(NSString *)text {
    if ([self.commandField.stringValue isEqualToString:text]) { return; }
    // While the field is being edited the field editor owns the text: setting
    // stringValue is ignored by the editor (and re-syncing later produced
    // franken-lines like ":open www.wp.pl:open www.wp"). Write through the
    // editor so the shown text is exactly `text`, then park the caret at the
    // end like GTK's completion_select.
    NSText *editor = [self.commandField currentEditor];
    if (editor) {
        editor.string = text;
        [editor setSelectedRange:NSMakeRange(text.length, 0)];
    } else {
        self.commandField.stringValue = text;
    }
}

// GTK parity: moving through the completion list rewrites the input line
// (completion_select via on_selection_changed); stepping over the first/last
// item clears the highlight and restores the text the user had typed
// (complete(): completion_next == FALSE -> completion_select(excomp.token));
// the next step in the same direction wraps to the far end.
- (void)stepDropdownSelectionBy:(NSInteger)direction {
    if ([self.completionDropdown moveSelectionBy:direction]) {
        NSString *v = self.completionDropdown.selectedValue;
        if (v.length > 0) {
            [self setCommandFieldTextSuppressingCompletion:[self.completionHead stringByAppendingString:v]];
        }
    } else {
        [self setCommandFieldTextSuppressingCompletion:self.completionBaseLine ?: @""];
    }
}

// GTK parity (src/ex.c complete()): the completion is started ONLY by Tab /
// Shift-Tab — never live while typing (main.c on_textbuffer_changed ignores
// edits during an active completion, so backspace just edits the buffer). If a
// session is already active and the input still holds the applied selection,
// step within it; otherwise (re)build the candidate list from the input.
- (void)completeCommandFieldDirection:(NSInteger)direction {
    NSString *line = self.commandField.stringValue;

    // ex.c: input == excomp.current -> completion_next / edge-restore.
    if (self.completionDropdown.hasCandidates) {
        NSString *applied = self.completionDropdown.selectedValue;
        if (applied.length > 0
            && [line isEqualToString:[self.completionHead stringByAppendingString:applied]]) {
            [self stepDropdownSelectionBy:direction];
            return;
        }
    }

    NSArray<NSString *> *strings = [self completionCandidatesForLine:line];
    if (!self.completionDropdown || strings.count == 0) {
        [self.completionDropdown dismiss];
        return;
    }

    // Track the completion session (GTK excomp): the head stays fixed while
    // candidates rewrite the trailing token, and the base line is what the
    // user typed (restored when stepping past the list edge).
    self.completionBaseLine = line;
    self.completionHead = [self completionHeadForLine:line];

    // Feed the completion-* CSS settings to the dropdown (parity with the GTK
    // #completion row styling).
    VimbConfig *cfg = [VimbConfig shared];
    NSString *css = [cfg getString:@"completion-css" defaultValue:@""];
    NSString *selCss = [cfg getString:@"completion-selected-css" defaultValue:@""];
    NSString *hovCss = [cfg getString:@"completion-hover-css" defaultValue:@""];
    if (![self.completionDropdown.completionCSS isEqualToString:css]) { self.completionDropdown.completionCSS = css; }
    if (![self.completionDropdown.completionSelectedCSS isEqualToString:selCss]) { self.completionDropdown.completionSelectedCSS = selCss; }
    if (![self.completionDropdown.completionHoverCSS isEqualToString:hovCss]) { self.completionDropdown.completionHoverCSS = hovCss; }

    NSMutableArray<CompletionCandidate *> *candidates = [NSMutableArray array];
    for (NSString *s in strings) {
        [candidates addObject:[CompletionCandidate candidateWithValue:s detail:nil]];
    }
    [self.completionDropdown updateWithCandidates:candidates];
    // Anchor at the bottom edge of the web container (= top of the docked
    // input row): the dropdown grows upward from there, over the page, like
    // the GTK completion box stacked above the input line. Width matches the
    // command field; the class clamps the frame inside the container.
    NSRect anchor = NSMakeRect(10, 0, self.webContainer.bounds.size.width - 22, 0);
    [self.completionDropdown presentRelativeToRect:anchor inView:self.webContainer];
    // completion_create -> completion_next(back): the first (last for
    // Shift-Tab) item is selected immediately and written to the input.
    [self stepDropdownSelectionBy:direction];
}

// Called when Enter is pressed while a completion row is highlighted: apply the
// selected completion to the trailing token of the current command line, then
// hand off to the normal command-line execution (parity with src/completion.c:
// choosing a candidate completes the text, Enter then runs the command).
- (void)commandLineCommittedWithCompletion:(NSString *)choice {
    // The live selection sync already rewrote the field to head+choice; only
    // rebuild when the field diverged. Never split the line on spaces — values
    // like URLs and search queries can contain them.
    NSString *cur = self.commandField.stringValue;
    if (![cur hasSuffix:choice]) {
        cur = [(self.completionHead ? self.completionHead : @"") stringByAppendingString:choice];
        [self setCommandFieldTextSuppressingCompletion:cur];
    }
    NSString *completed = cur;
    VimMode m = self.vim.mode;
    [self.completionDropdown dismiss];
    // Unified executor (parity with the plain-Enter path): search and command
    // both run through commandLineExecuted so the prompt char is stripped and
    // search history is recorded consistently.
    VimbExCmdResult res = [self commandLineExecuted:completed];
    [self.vim reset];
    if ((res & VimbExCmdResultKeepInput) && m == VimModeCommand) {
        [self.window makeFirstResponder:self.commandField];
    } else {
        [self hideCommandLine];
    }
}

#pragma mark - Menu / responder actions

- (void)newTab:(id)sender { [self newTabInWindow]; }
- (void)closeTab:(id)sender { [self closeActiveTab]; }
- (void)goBack:(id)sender { [self goBack]; }
- (void)goForward:(id)sender { [self goForward]; }
- (void)reloadPage:(id)sender { [self reloadPage]; }
- (void)stopLoading:(id)sender { [self.activeTab.webView stopLoading:nil]; }
- (void)zoomIn:(id)sender {
    self.activeTab.webView.magnification = self.activeTab.webView.magnification + 0.1;
}
- (void)zoomOut:(id)sender {
    self.activeTab.webView.magnification = MAX(0.5, self.activeTab.webView.magnification - 0.1);
}
- (void)actualSize:(id)sender {
    self.activeTab.webView.magnification = 1.0;
}

@end

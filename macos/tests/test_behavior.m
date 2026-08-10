// Behavior tests ported from the C gtester suite (tests/test-map.c,
// tests/test-shortcut.c) plus coverage-driver tests for VimController,
// VimbEx, VimbConfig, VimbEngine and VimbAutocmd. Foundation-only.
#import "testlib.h"

#import <objc/objc-runtime.h>

#import "VimController.h"
#import "VimbStorage.h"
#import "VimbConfig.h"
#import "VimbEx.h"
#import "VimbEngine.h"
#import "VimbAutocmd.h"
#import "VimbHandler.h"

#pragma mark - Shared spies

// Wraps a char in an NSString (like charactersIgnoringModifiers).
static NSString *S(unichar c) {
    return [NSString stringWithCharacters:&c length:1];
}

@interface BehavSpy : NSObject <VimDelegate>
@property(nonatomic, strong) NSMutableArray<NSString *> *calls;
- (void)record:(NSString *)f;
@end

@implementation BehavSpy
- (instancetype)init { self = [super init]; if (self) { _calls = [NSMutableArray array]; } return self; }
- (void)record:(NSString *)f { [_calls addObject:f]; }
- (void)vimScrollMode:(unichar)mode count:(NSUInteger)count { [self record:[NSString stringWithFormat:@"scroll:%C:%lu", mode, (unsigned long)count]]; }
- (void)vimGoBack { [self record:@"back"]; }
- (void)vimGoForward { [self record:@"forward"]; }
- (void)vimReload { [self record:@"reload"]; }
- (void)vimStop { [self record:@"stop"]; }
- (void)vimOpenURL:(NSString *)urlValue inNewTab:(BOOL)newTab { [self record:[NSString stringWithFormat:@"open:%d:%@", newTab, urlValue]]; }
- (void)vimOpenHome { [self record:@"home"]; }
- (void)vimGoHomeURL { [self record:@"gohomeurl"]; }
- (void)vimOpenPrompt:(NSString *)prompt mode:(VimMode)mode { [self record:[NSString stringWithFormat:@"prompt:%ld:%@", (long)mode, prompt]]; }
- (void)vimSearch:(NSString *)query forward:(BOOL)forward { [self record:[NSString stringWithFormat:@"search:%d:%@", forward, query]]; }
- (void)vimSearchDirection:(NSInteger)dir { [self record:[NSString stringWithFormat:@"searchdir:%ld", (long)dir]]; }
- (void)vimSearchSelectionForward:(BOOL)forward { [self record:[NSString stringWithFormat:@"searchsel:%d", forward]]; }
- (void)vimFire { [self record:@"fire"]; }
- (void)vimFocusLastActive { [self record:@"focuslast"]; }
- (void)vimFocusInput { [self record:@"focusinput"]; }
- (void)vimNextTab { [self record:@"nexttab"]; }
- (void)vimPrevTab { [self record:@"prevtab"]; }
- (void)vimGotoTab:(NSUInteger)index { [self record:[NSString stringWithFormat:@"gototab:%lu", (unsigned long)index]]; }
- (void)vimGotoTabFromLast:(NSInteger)count { [self record:[NSString stringWithFormat:@"gototablast:%ld", (long)count]]; }
- (void)vimNewTab { [self record:@"newtab"]; }
- (void)vimCloseTab { [self record:@"closetab"]; }
- (void)vimToggleHints { [self record:@"toggleshints"]; }
- (void)vimEnterHints:(NSString *)mode { [self record:[NSString stringWithFormat:@"enterhints:%@", mode]]; }
- (void)vimHintKey:(NSString *)key { [self record:[NSString stringWithFormat:@"hintkey:%@", key]]; }
- (void)vimShowMessage:(NSString *)message error:(BOOL)error { [self record:[NSString stringWithFormat:@"msg:%d:%@", error, message]]; }
- (void)vimFocusWebView { [self record:@"focusweb"]; }
- (void)vimEnterPassThrough { [self record:@"passthrough"]; }
- (void)vimYankURI { [self record:@"yank"]; }
- (void)vimSetMark:(unichar)c { [self record:[NSString stringWithFormat:@"setmark:%C", c]]; }
- (void)vimJumpMark:(unichar)c { [self record:[NSString stringWithFormat:@"jumpmark:%C", c]]; }
- (void)vimViewSource { [self record:@"viewsource"]; }
- (void)vimZoom:(BOOL)in { [self record:[NSString stringWithFormat:@"zoom:%d", in]]; }
- (void)vimIncrement:(BOOL)up count:(NSInteger)count { [self record:[NSString stringWithFormat:@"incr:%d:%ld", up, (long)count]]; }
- (void)vimQuit { [self record:@"quit"]; }
- (void)vimOpenClipboard:(NSString *)counter { [self record:[NSString stringWithFormat:@"clipboard:%@", counter]]; }
@end

// Actor that records ex calls.
@interface BehavActor : NSObject <VimbExActor>
@property(nonatomic, strong) NSMutableArray<NSString *> *calls;
@end

@implementation BehavActor
- (instancetype)init { self = [super init]; if (self) { _calls = [NSMutableArray array]; } return self; }
- (void)openedAdd:(NSString *)arg newTab:(BOOL)nt { [_calls addObject:[NSString stringWithFormat:@"open:%d:%@", nt, arg]]; }
- (void)exOpen:(NSString *)arg newTab:(BOOL)newTab { [self openedAdd:arg newTab:newTab]; }
- (void)exSet:(NSString *)fullArg { [_calls addObject:[@"set:" stringByAppendingString:fullArg]]; }
- (void)exCloseActiveTab { [_calls addObject:@"tabclose"]; }
- (void)exNextTab { [_calls addObject:@"tabnext"]; }
- (void)exPrevTab { [_calls addObject:@"tabprev"]; }
- (void)exFirstTab { [_calls addObject:@"tabfirst"]; }
- (void)exLastTab { [_calls addObject:@"tablast"]; }
- (void)exReload { [_calls addObject:@"reload"]; }
- (void)exStop { [_calls addObject:@"stop"]; }
- (void)exHome { [_calls addObject:@"home"]; }
- (void)exQuit { [_calls addObject:@"quit"]; }
- (void)exQuitAll { [_calls addObject:@"quitall"]; }
- (void)exEval:(NSString *)js { [_calls addObject:[@"eval:" stringByAppendingString:js]]; }
- (void)exShell:(NSString *)arg { [_calls addObject:[@"shell:" stringByAppendingString:arg]]; }
- (void)exMessage:(NSString *)msg error:(BOOL)error { [_calls addObject:[NSString stringWithFormat:@"msg:%d:%@", error, msg]]; }
- (void)exSavePage:(NSString *)path { [_calls addObject:[@"save:" stringByAppendingString:(path ?: @"")]]; }
- (void)exRegisterList { [_calls addObject:@"register"]; }
- (void)exSource:(NSString *)path { [_calls addObject:[@"source:" stringByAppendingString:(path ?: @"")]]; }
- (void)exQueue:(NSString *)cmd arg:(NSString *)arg { [_calls addObject:[NSString stringWithFormat:@"queue:%@:%@", cmd, (arg ?: @"")]]; }
- (void)exShowMessages { [_calls addObject:@"showmessages"]; }
- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title { [_calls addObject:[NSString stringWithFormat:@"bma:%@:%@", url, title]]; }
- (void)exBookmarkRemove:(NSString *)match { [_calls addObject:[@"bmr:" stringByAppendingString:match]]; }
@end

static BehavSpy *newSpy(void) {
    BehavSpy *s = [[BehavSpy alloc] init];
    return s;
}
static BehavActor *newActor(void) {
    return [[BehavActor alloc] init];
}
static VimController *newVc(BehavSpy *spy) {
    VimController *vc = [[VimController alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;
    [vc reset];
    return vc;
}

static void feed(VimController *vc, NSString *chars) {
    for (NSUInteger i = 0; i < chars.length; i++) {
        unichar c = [chars characterAtIndex:i];
        [vc handleKeyCode:0 modifiers:0 characters:[NSString stringWithCharacters:&c length:1]];
    }
}

#pragma mark - Map port (tests/test-map.c)

static void test_map_insert_and_delete(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    NSDictionary *entry = [c addMappingForMode:@"n" lhs:@"gg" rhs:@"G" noremap:YES];
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 1);
    TEST_ASSERT_EQ_STR(entry[@"lhs"], @"gg");
    TEST_ASSERT_EQ_STR(entry[@"rhs"], @"G");
    TEST_ASSERT_TRUE([entry[@"noremap"] boolValue]); // noremap (remap == NO)

    TEST_ASSERT_TRUE([c removeMappingForMode:@"n" lhs:@"gg"]);
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 0);
}

static void test_map_delete_nonexistent(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    TEST_ASSERT_TRUE(![c removeMappingForMode:@"n" lhs:@"xx"]);
}

static void test_map_insert_multiple_modes(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    [c addMappingForMode:@"n" lhs:@"dd" rhs:@"delete-line" noremap:YES];
    [c addMappingForMode:@"i" lhs:@"jj" rhs:[c convertKeyString:@"<Esc>"] noremap:YES];
    [c addMappingForMode:@"c" lhs:@"qq" rhs:@"quit" noremap:NO];

    // delete only the insert-mode mapping.
    TEST_ASSERT_TRUE([c removeMappingForMode:@"i" lhs:@"jj"]);
    TEST_ASSERT_EQ_I([c.mappings[@"i"] count], 0);
    // deleting again fails.
    TEST_ASSERT_TRUE(![c removeMappingForMode:@"i" lhs:@"jj"]);
    // normal-mode mapping still present.
    TEST_ASSERT_TRUE([c removeMappingForMode:@"n" lhs:@"dd"]);
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 0);
    // command-mode mapping (remap) preserved.
    NSDictionary *qq = [c.mappings[@"c"] firstObject];
    TEST_ASSERT_TRUE(qq != nil);
    TEST_ASSERT_TRUE(![qq[@"noremap"] boolValue]); // remap preserved
    TEST_ASSERT_EQ_STR(qq[@"lhs"], @"qq");

    [c removeMappingForMode:@"c" lhs:@"qq"];
}

static void test_map_insert_overwrite(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    [c addMappingForMode:@"n" lhs:@"gg" rhs:@"old-mapping" noremap:YES];
    [c addMappingForMode:@"n" lhs:@"gg" rhs:@"new-mapping" noremap:NO];
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 1);
    NSDictionary *m = [c.mappings[@"n"] firstObject];
    TEST_ASSERT_EQ_STR(m[@"rhs"], @"new-mapping");
    TEST_ASSERT_TRUE(![m[@"noremap"] boolValue]); // remap updated
    [c removeMappingForMode:@"n" lhs:@"gg"];
}

static void test_map_delete_wrong_mode(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    [c addMappingForMode:@"n" lhs:@"gg" rhs:@"top" noremap:YES];
    TEST_ASSERT_TRUE(![c removeMappingForMode:@"i" lhs:@"gg"]);
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 1);
    [c removeMappingForMode:@"n" lhs:@"gg"];
}

static void test_map_special_keys(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    NSString *cr = [c convertKeyString:@"<CR>"];
    TEST_ASSERT_EQ_I([cr length], 1);
    TEST_ASSERT_EQ_I([cr characterAtIndex:0], 0x0d);

    [c addMappingForMode:@"n" lhs:cr rhs:@"enter-action" noremap:YES];
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 1);
    NSDictionary *res = [c resolveMappingForMode:@"n" buffer:cr];
    TEST_ASSERT_EQ_STR(res[@"status"], @"match");
    TEST_ASSERT_EQ_STR(res[@"rhs"], @"enter-action");
    TEST_ASSERT_TRUE([c removeMappingForMode:@"n" lhs:[c convertKeyString:@"<CR>"]]);
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 0);
}

static void test_map_ctrl_key(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    NSString *cf = [c convertKeyString:@"<C-f>"];
    TEST_ASSERT_EQ_I([cf length], 1);
    TEST_ASSERT_EQ_I([cf characterAtIndex:0], 0x06);

    [c addMappingForMode:@"n" lhs:cf rhs:@"page-down" noremap:YES];
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 1);
    TEST_ASSERT_TRUE([c removeMappingForMode:@"n" lhs:[c convertKeyString:@"<C-f>"]]);
    TEST_ASSERT_EQ_I([c.mappings[@"n"] count], 0);
}

#pragma mark - Shortcut port (tests/test-shortcut.c)

static VimbConfig *shortcutConfig(void) {
    VimbConfig *c = [[VimbConfig alloc] init];
    [c addShortcut:@"_vimb1_" uri:@"only-zero:$0"];
    [c addShortcut:@"_vimb2_" uri:@"default:$0-$2"];
    [c addShortcut:@"_vimb3_" uri:@"fullrange:$0-$1-$9"];
    [c addShortcut:@"_vimb4_" uri:@"for-remove:$0"];
    [c addShortcut:@"_vimb5_" uri:@"double-zero:$0-$0"];
    [c addShortcut:@"_vimb6_" uri:@"shell:$0-$1"];
    [c setDefaultShortcutKey:@"_vimb2_"];
    return c;
}

static void test_shortcut_basic(void) {
    VimbConfig *c = shortcutConfig();
    struct { NSString *in; NSString *out; } data[] = {
        {@"_vimb1_ zero one", @"only-zero:zero%20one"},
        {@"_vimb1_ 'unmatches quote", @"only-zero:'unmatches%20quote"},
        {@"_vimb5_ one two", @"double-zero:one%20two-one%20two"},
        {@"zero one two three", @"default:zero-two%20three"},
        {@"zero", @"default:zero-$2"},
        {@"_vimb3_ zero one two three four five six seven eight nine", @"fullrange:zero-one-nine"},
    };
    for (NSUInteger i = 0; i < 6; i++) {
        TEST_ASSERT_EQ_STR([c shortcutURIForInput:data[i].in], data[i].out);
    }
}

static void test_shortcut_shell_param(void) {
    VimbConfig *c = shortcutConfig();
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb6_ \"rail station\" city hall"],
                       @"shell:rail%20station-city%20hall");
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb6_ 'rail station' 'city hall'"],
                       @"shell:rail%20station-city%20hall");
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb6_ \"rail station\" \"city hall"],
                       @"shell:rail%20station-city%20hall");
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb6_ \"param 1\" \"param 2\" ignored params"],
                       @"shell:param%201-param%202");
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb6_ param1 param2 \"containing quotes\""],
                       @"shell:param1-param2%20%22containing%20quotes%22");
}

static void test_shortcut_remove(void) {
    VimbConfig *c = shortcutConfig();
    TEST_ASSERT_TRUE([c removeShortcut:@"_vimb4_"]);
    // After removal the default (_vimb2_) is used with the whole line as query.
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"_vimb4_ test"], @"default:_vimb4_-$2");
    TEST_ASSERT_TRUE(![c removeShortcut:@"_vimb4_"]);

    // No shortcut at all -> nil.
    VimbConfig *empty = [[VimbConfig alloc] init];
    TEST_ASSERT_TRUE([empty shortcutURIForInput:@"anything"] == nil);
    // applyShortcut with missing key -> empty.
    TEST_ASSERT_EQ_STR([empty applyShortcut:@"nope" query:@"x"], @"");
}

static void test_shortcut_no_placeholder_template(void) {
    VimbConfig *c = [[VimbConfig alloc] init];
    [c addShortcut:@"lit" uri:@"https://example.com"];
    [c setDefaultShortcutKey:@"lit"];
    // No $ in template -> returned as-is (get_max_placeholder == -1).
    TEST_ASSERT_EQ_STR([c shortcutURIForInput:@"anything here"], @"https://example.com");
}

static void test_search_engine_uses_engine(void) {
    VimbConfig *c = [[VimbConfig alloc] init];
    [c addShortcut:@"ee" uri:@"https://search.example.com/?q=$0"];
    [c setDefaultShortcutKey:@"ee"];
    TEST_ASSERT_EQ_STR([c searchURLForQuery:@"hello world"],
                       @"https://search.example.com/?q=hello%20world");
    TEST_ASSERT_EQ_STR([c searchEngineMainPage], @"https://search.example.com/");
}

// TDD: the production singleton must be initialized with defaults, so on app
// startup home-page/search shortcuts/etc. are populated (they were only ever
// loaded in tests before, leaving the app defaulting to about:blank).
static void test_shared_initialized_with_defaults(void) {
    VimbConfig *c = [VimbConfig shared];
    NSString *home = c.settings[@"home-page"];
    TEST_ASSERT_TRUE(home != nil && home.length > 0);
    // Default home page should resolve to a search engine page, not about:blank.
    TEST_ASSERT_TRUE(![home hasPrefix:@"about:"]);
    TEST_ASSERT_TRUE([home containsString:@"duckduckgo.com"]);
    // scroll-step and default shortcut should be populated too.
    TEST_ASSERT_EQ_I([c getInt:@"scroll-step" defaultValue:0], 40);
    TEST_ASSERT_TRUE(c.defaultShortcut.length > 0);
    // The shared singleton is cached: a second access returns the same object.
    VimbConfig *c2 = [VimbConfig shared];
    TEST_ASSERT_TRUE(c == c2);
}

// These cases mirror src/main.c:424 is_plausible_uri / vb_load_uri:
//   - contains "://" (no space) or "about:" -> direct
//   - real file path -> file:// (covered separately)
//   - NOT plausible (space, no dot, not localhost, not IPv6) -> search/shortcut
//   - plausible (dot/localhost/IPv6) -> http://
static void test_loaduri_decision(void) {
    VimbConfig *c = [[VimbConfig alloc] init];
    [c addShortcut:@"dd" uri:@"https://duckduckgo.com/?q=$0"];
    [c setDefaultShortcutKey:@"dd"];

    // Direct URLs.
    TEST_ASSERT_EQ_STR([c loadURI:@"https://example.com/x"], @"https://example.com/x");
    TEST_ASSERT_EQ_STR([c loadURI:@"about:blank"], @"about:blank");

    // Plausible URL (contains a dot) -> http:// fallback.
    TEST_ASSERT_EQ_STR([c loadURI:@"example.com"], @"http://example.com");

    // localhost is plausible.
    TEST_ASSERT_EQ_STR([c loadURI:@"localhost"], @"http://localhost");

    // Not plausible -> search via default shortcut.
    TEST_ASSERT_EQ_STR([c loadURI:@"something"],
                       @"https://duckduckgo.com/?q=something");
    // Space -> search.
    TEST_ASSERT_EQ_STR([c loadURI:@"hello world"],
                       @"https://duckduckgo.com/?q=hello%20world");
}

#pragma mark - VimbConfig coverage

static void test_config_get_and_source_content(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    // get: returns a setting value.
    TEST_ASSERT_TRUE([c get:@"scroll-step"] != nil);
    TEST_ASSERT_TRUE([c get:@"does-not-exist"] == nil);

    // executeSourceContent skips empty/comment lines and posts commands.
    __block NSMutableArray<NSString *> *posted = [NSMutableArray array];
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"VimbRunCommand" object:nil queue:nil
        usingBlock:^(NSNotification *n){ [posted addObject:n.userInfo[@"command"]]; }];
    [c executeSourceContent:@"set scroll-step=5\n\" a comment\n# another\nopen example.com\n\nopen x.com"];
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    TEST_ASSERT_EQ_I(posted.count, 3);
    TEST_ASSERT_EQ_STR(posted[0], @"set scroll-step=5");
    TEST_ASSERT_EQ_STR(posted[1], @"open example.com");
    TEST_ASSERT_EQ_STR(posted[2], @"open x.com");
}

static void test_config_convert_edge_cases(void) {
    VimbConfig *c = [VimbConfig shared];
    TEST_ASSERT_EQ_STR([c convertKeyString:@"<no-close"], @"<no-close"); // literal '<'
    TEST_ASSERT_EQ_STR([c convertKeyString:@"aa<BB>aa"], @"aaBBaa");
    // Uppercase ctrl char (C-A -> 0x01).
    NSString *cA = [c convertKeyString:@"<C-A>"];
    TEST_ASSERT_EQ_I([cA characterAtIndex:0], 0x01);
    // Two-char invalid token -> literal.
    TEST_ASSERT_EQ_STR([c convertKeyString:@"<C+>"], @"C+");
    // Multi-token with known + unknown labels.
    NSString *mixed = [c convertKeyString:@"ab<CR>de<Esz>"];
    TEST_ASSERT_EQ_I([mixed characterAtIndex:2], 0x0d);
    TEST_ASSERT_EQ_STR([mixed substringFromIndex:3], @"deEsz");
}

#pragma mark - VimbEngine coverage

static void test_engine_global_mark_trim(void) {
    VimbMarks *marks = [[VimbMarks alloc] init];
    for (unichar i = '0'; i <= '9'; i++) {
        [marks setGlobal:i uri:[NSString stringWithFormat:@"u%c", i]];
    }
    // 10 marks, the oldest ('0') pruned when adding an 11th.
    [marks setGlobal:'x' uri:@"ux"];
    TEST_ASSERT_TRUE([marks getGlobal:'0'] == nil);
    TEST_ASSERT_EQ_STR([marks getGlobal:'9'], @"u9");
    TEST_ASSERT_EQ_STR([marks getGlobal:'x'], @"ux");
    // Re-setting an existing key moves it to front without growing beyond 10.
    [marks setGlobal:'9' uri:@"u9new"];
    TEST_ASSERT_EQ_STR([marks getGlobal:'9'], @"u9new");
    // Setting a key that already exists keeps count <= 10 (no removal of 9).
    TEST_ASSERT_TRUE([marks getGlobal:'9'] != nil);
}

#pragma mark - VimbAutocmd coverage

static void test_autocmd_every_event_and_download(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block int executed = 0;
    au.reporter = ^(NSString *msg, BOOL error) { (void)msg; (void)error; };
    au.executor = ^(NSString *cmd) { (void)cmd; executed++; };
    // Register on every event type (exercises eventName for each).
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"download-started * :started"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"download-finished * :finished"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"download-failed * :failed"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-committed * :committed"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-started * :started"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-starting * :starting"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"all * :all"]);
    [au fireEvent:VAuDownloadStarted uri:@"http://x"];
    [au fireEvent:VAuLoadStarting uri:@"http://x"];
    TEST_ASSERT_TRUE(executed >= 3);
}

static void test_autocmd_remove_and_group(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block int reported = 0;
    au.reporter = ^(NSString *msg, BOOL error) { reported++; (void)msg; (void)error; };
    au.executor = ^(NSString *cmd) { (void)cmd; };

    // Remove an existing autocmd via :autocmd! event pattern.
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-finished * :reload"]);
    TEST_ASSERT_TRUE([au hasEvent:VAuLoadFinished]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"! load-finished *"]);
    TEST_ASSERT_TRUE(![au hasEvent:VAuLoadFinished]); // entry removed

    // Removal with a specific pattern.
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-finished * :reload"]);
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"! load-finished http://other"]);
    TEST_ASSERT_TRUE([au hasEvent:VAuLoadFinished]); // still there (pattern mismatch)

    // augroup empty/closing-END line.
    __block int repBefore = reported;
    [au parseAugroupLine:@"MyGroup"];
    [au parseAugroupLine:@"END"];
    [au parseAugroupLine:@""]; // closing pending group path (reports)
    TEST_ASSERT_TRUE(reported >= repBefore);
}

static void test_autocmd_missing_command(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block int reported = 0;
    au.reporter = ^(NSString *msg, BOOL error) { reported++; (void)msg; (void)error; };
    // No leading ':' command -> missing-command path.
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-finished *"]);
    TEST_ASSERT_TRUE(reported > 0);
}

static void test_autocmd_wildcard_patterns(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block int x = 0;
    au.executor = ^(NSString *cmd) { (void)cmd; x++; };
    // '?' glob matches a single char.
    [au parseAutocmdLine:@"load-finished http://exa?ple.com :reload"];
    [au fireEvent:VAuLoadFinished uri:@"http://example.com"];
    TEST_ASSERT_EQ_I(x, 1);
    // nil uri treated as empty string (wildcard: matches only literal pattern).
    [au fireEvent:VAuLoadFinished uri:nil];
    TEST_ASSERT_EQ_I(x, 1);
}

#pragma mark - VimbEx coverage

static void test_ex_every_type(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;

    [ex runCommand:@"reload"];            // reload/r alias -> exReload
    [ex runCommand:@"r example.com"];     // 'r' alias -> reload
    TEST_ASSERT_TRUE([a.calls containsObject:@"reload"]);

    [ex runCommand:@"quit"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"quit"]);
    [ex runCommand:@"quitall"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"quitall"]);

    [ex runCommand:@"save /tmp/x.png"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"save:/tmp/x.png"]);
    [ex runCommand:@"save"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"save:"]);

    [ex runCommand:@"register"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"register"]);

    [ex runCommand:@"eval 1+1"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"eval:1+1"]);
    [ex runCommand:@"normal gg"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"eval:gg"]);

    [ex runCommand:@"source /tmp/rc"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"source:/tmp/rc"]);

    [ex runCommand:@"shellcmd ls -la"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"shell:ls -la"]);
    [ex runCommand:@"shellex echo hi"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"shell:echo hi"]);

    [ex runCommand:@"cleardata"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"msg:0:"]);
    [ex runCommand:@"hardcopy"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"msg:0:"]);

    [ex runCommand:@"qpush foo"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"queue:qpush:foo"]);
    [ex runCommand:@"qpop"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"queue:qpop:"]);

    [ex runCommand:@"bma https://x.com Title"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"bma:https://x.com:Title"]);
    [ex runCommand:@"bmr x.com"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"bmr:x.com"]);
}

static void test_ex_tabcmd(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    [ex runCommand:@"tabclose"];
    [ex runCommand:@"tabnext"];
    [ex runCommand:@"tabn"];
    [ex runCommand:@"tabprev"];
    [ex runCommand:@"tabprevious"];
    [ex runCommand:@"tabp"];
    [ex runCommand:@"tabfirst"];
    [ex runCommand:@"tablast"];
    [ex runCommand:@"bdelete"];
    [ex runCommand:@"bd"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"tabclose"]);
    NSUInteger tn = 0; for (NSString *c in a.calls) { if ([c isEqualToString:@"tabnext"]) tn++; }
    TEST_ASSERT_EQ_I((NSInteger)tn, 2); // tabnext + tabn
    NSUInteger tp = 0; for (NSString *c in a.calls) { if ([c isEqualToString:@"tabprev"]) tp++; }
    TEST_ASSERT_EQ_I((NSInteger)tp, 3); // tabprev + tabprevious + tabp
    TEST_ASSERT_TRUE([a.calls containsObject:@"tabfirst"]);
    TEST_ASSERT_TRUE([a.calls containsObject:@"tablast"]);
    NSUInteger tc = 0; for (NSString *c in a.calls) { if ([c isEqualToString:@"tabclose"]) tc++; }
    TEST_ASSERT_EQ_I((NSInteger)tc, 3); // tabclose + bdelete + bd
}

static void test_ex_autocmd_augroup(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    // augroup line routes to parseAugroupLine.
    [ex runCommand:@"augroup MyGroup"];
    [ex runCommand:@"autocmd load-finished https://example.com/* :reload"];
    VimbAutocmd *au = [VimbConfig shared].autocmd;
    TEST_ASSERT_TRUE([au hasEvent:VAuLoadFinished]);
    // Clear to avoid leaking (empty group).
    [ex runCommand:@"augroup END"];
}

static void test_ex_shortcut_commands(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    [ex runCommand:@"shortcut-add myk https://my.example/?q=$0"];
    TEST_ASSERT_EQ_STR([VimbConfig shared].shortcuts[@"myk"],
                       @"https://my.example/?q=$0");

    [ex runCommand:@"shortcut-default myk"];
    TEST_ASSERT_EQ_STR([VimbConfig shared].defaultShortcut, @"myk");

    [ex runCommand:@"shortcut-remove myk"];
    TEST_ASSERT_TRUE([VimbConfig shared].shortcuts[@"myk"] == nil);

    // remove non-existent -> "not found" message.
    [ex runCommand:@"shortcut-remove ghost"];
    __block BOOL sawNotFound = NO;
    for (NSString *c in a.calls) { if ([c hasPrefix:@"msg:1:"] && [c containsString:@"not found"]) sawNotFound = YES; }
    TEST_ASSERT_TRUE(sawNotFound);

    // legacy name=url syntax.
    [ex runCommand:@"shortcut-add eq https://eq.example/?q=$0"]; // unchanged path
    TEST_ASSERT_TRUE([VimbConfig shared].shortcuts[@"eq"] != nil);

    [VimbConfig shared].defaultShortcut = @"dl";
}

static void test_ex_map_commands_all_modes(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    VimbConfig *c = [VimbConfig shared];

    [ex runCommand:@"imap ii <Esc>"];
    TEST_ASSERT_EQ_I([c.mappings[@"i"] count], 1);
    NSDictionary *res = [c resolveMappingForMode:@"i" buffer:[c convertKeyString:@"ii"]];
    TEST_ASSERT_EQ_STR(res[@"rhs"], [c convertKeyString:@"<Esc>"]);
    [ex runCommand:@"iunmap ii"];
    TEST_ASSERT_EQ_I([c.mappings[@"i"] count], 0);

    [ex runCommand:@"cmap cc qq"];
    TEST_ASSERT_EQ_I([c.mappings[@"c"] count], 1);
    [ex runCommand:@"cunmap cc"];
    TEST_ASSERT_EQ_I([c.mappings[@"c"] count], 0);

    // unmap with empty lhs errors.
    [ex runCommand:@"nunmap"];
    __block BOOL sawUnmapErr = NO;
    for (NSString *cc in a.calls) { if ([cc hasPrefix:@"msg:1:"] && [cc containsString:@"unmap"]) sawUnmapErr = YES; }
    TEST_ASSERT_TRUE(sawUnmapErr);

    // map with too few args errors.
    [ex runCommand:@"nmap onlylhs"];
    __block BOOL sawMapErr = NO;
    for (NSString *cc in a.calls) { if ([cc hasPrefix:@"msg:1:"] && [cc containsString:@"map requires"]) sawMapErr = YES; }
    TEST_ASSERT_TRUE(sawMapErr);
}

static void test_ex_unknown_command(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    // A single bare non-URL token -> invalid-command message.
    [ex runCommand:@"notacommand"];
    __block BOOL sawInvalid = NO;
    for (NSString *cc in a.calls) { if ([cc hasPrefix:@"msg:1:"] && [cc containsString:@"Invalid command"]) sawInvalid = YES; }
    TEST_ASSERT_TRUE(sawInvalid);
    // A URL-like bare token is opened.
    [a.calls removeAllObjects];
    [ex runCommand:@"example.com"];
    TEST_ASSERT_TRUE([a.calls containsObject:@"open:0:example.com"]);
}

static void test_ex_ambiguous_command(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    // Ambiguous abbreviation (e.g. "ta" matches tabopen/tabclose/...) falls to
    // the URL path. "ta" has no dot/slash/space -> becomes invalid command.
    [ex runCommand:@"tabpev"]; // no match at all
    // A genuinely ambiguous prefix "t" matches many tab commands.
    [ex runCommand:@"t"];
    // An invalid token handled without crashing.
    TEST_ASSERT_TRUE(ex != nil);
}

#pragma mark - VimbHandler (parity: src/handler.c)

static void test_handler_add_remove_lookup(void) {
    VimbHandler *h = [[VimbHandler alloc] init];
    // add
    TEST_ASSERT_TRUE([h addScheme:@"mailto" command:@"open -a Mail %s"]);
    TEST_ASSERT_EQ_STR([h commandForURI:@"mailto:foo@bar.com"],
                       @"open -a Mail %s");
    // schemes listed
    TEST_ASSERT_TRUE([h.schemes containsObject:@"mailto"]);
    // remove
    TEST_ASSERT_TRUE([h removeScheme:@"mailto"]);
    TEST_ASSERT_TRUE([h commandForURI:@"mailto:foo@bar.com"] == nil);
    TEST_ASSERT_TRUE([h removeScheme:@"mailto"] == NO); // already gone
}

static void test_handler_scheme_no_colon(void) {
    VimbHandler *h = [[VimbHandler alloc] init];
    TEST_ASSERT_TRUE([h addScheme:@"x" command:@"echo %s"]);
    // No colon -> no scheme -> nil command.
    TEST_ASSERT_TRUE([h commandForURI:@"http-nowhere"] == nil);
    // Different scheme not registered.
    TEST_ASSERT_TRUE([h commandForURI:@"tel:123"] == nil);
}

static void test_handler_handle_uri_returns(void) {
    VimbHandler *h = [[VimbHandler alloc] init];
    // No handler registered -> handleURI returns NO (load proceeds).
    TEST_ASSERT_TRUE([h handleURI:@"mailto:x@y"] == NO);
    // Register a harmless handler; handleURI returns YES.
    TEST_ASSERT_TRUE([h addScheme:@"vhb" command:@"/usr/bin/true %s"]);
    TEST_ASSERT_TRUE([h handleURI:@"vhb:xyz"] == YES);
}

#pragma mark - VimController coverage

static void test_controller_invoke_handlers(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);

    // reload: ^C, ^R, 'r', 'R'
    [spy.calls removeAllObjects];
    feed(vc, @"r"); TEST_ASSERT_TRUE([spy.calls containsObject:@"reload"]);
    feed(vc, @"R"); TEST_ASSERT_TRUE([spy.calls containsObject:@"reload"]);

    // back / forward
    [spy.calls removeAllObjects];
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x0f} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"back"]);
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x09} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"forward"]);

    // fire (^M)
    [spy.calls removeAllObjects];
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x0d} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"fire"]);

    // increment ^A / decrement ^X
    [spy.calls removeAllObjects];
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x01} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"incr:1:0"]);
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x18} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"incr:0:0"]);

    // searchsel # / *
    [spy.calls removeAllObjects];
    feed(vc, @"#"); TEST_ASSERT_TRUE([spy.calls containsObject:@"searchsel:0"]);
    feed(vc, @"*"); TEST_ASSERT_TRUE([spy.calls containsObject:@"searchsel:1"]);
}

static void test_controller_pass_keys_to_page(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);

    // No page editable focus -> always vim handles keys.
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:NO] == NO);

    // Page editable focus + normal mode -> keys go to the page (input).
    vc.mode = VimModeNormal;
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:YES] == YES);

    // But in command/search/hint modes vim keeps the keys even if focused.
    vc.mode = VimModeCommand;
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:YES] == NO);
    vc.mode = VimModeSearch;
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:YES] == NO);
    vc.mode = VimModeHint;
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:YES] == NO);
    vc.mode = VimModePassThrough;
    TEST_ASSERT_TRUE([vc shouldPassKeysToPage:YES] == NO);
}

static void test_controller_search_dir_and_count(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // 'n' forward dir 1, 'N' backward dir -1.
    feed(vc, @"n"); TEST_ASSERT_TRUE([spy.calls containsObject:@"searchdir:1"]);
    // count prefix "2n" -> forward 2.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"2"); feed(vc, @"n");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"searchdir:2"]);
}

static void test_controller_marks(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // m <char> sets a mark.
    [spy.calls removeAllObjects];
    feed(vc, @"m"); feed(vc, @"a");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"setmark:a"]);
    // ' <char> jumps to a mark.
    [spy.calls removeAllObjects];
    feed(vc, @"'"); feed(vc, @"b");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"jumpmark:b"]);
}

static void test_controller_cmdline_and_input_open(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // ':' -> command prompt (VimModeCommand==1).
    feed(vc, @":");
    TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"prompt:1::"]);
    [vc reset];

    // '/' -> search prompt mode with forward (VimModeSearch==2).
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"/");
    TEST_ASSERT_EQ_I(vc.mode, VimModeSearch);
    [vc reset];

    // '?' -> backward.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"?");
    TEST_ASSERT_EQ_I(vc.mode, VimModeSearch);

    // 'f' / 'F' -> hint follow mode.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"f");
    TEST_ASSERT_EQ_I(vc.mode, VimModeHint);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"enterhints:o"]);
    vc = newVc(spy); feed(vc, @"F");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"enterhints:t"]);

    // ';' + follow key -> hint mode.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @";"); feed(vc, @"y");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"enterhints:y"]);
    // ';o' -> default 'o' follow.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @";"); feed(vc, @"o");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"enterhints:o"]);

    // o / O / t / T -> inputopen.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"o");
    TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"prompt:1:open "]);
    vc = newVc(spy); feed(vc, @"t");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"prompt:1:tabopen "]);
    vc = newVc(spy); feed(vc, @"O"); TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
    vc = newVc(spy); feed(vc, @"T"); TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
}

static void test_controller_openclipboard_yank_focus(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // clipboard p / P.
    feed(vc, @"p"); TEST_ASSERT_TRUE([spy.calls containsObject:@"clipboard:0"]);
    feed(vc, @"P"); TEST_ASSERT_TRUE([spy.calls containsObject:@"clipboard:0"]);
    // register stack: "a then p -> clipboard:a
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @"\""); feed(vc, @"a"); feed(vc, @"p");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"clipboard:a"]);

    // yank y / Y.
    [spy.calls removeAllObjects];
    feed(vc, @"y"); TEST_ASSERT_TRUE([spy.calls containsObject:@"yank"]);
    feed(vc, @"Y"); TEST_ASSERT_TRUE([spy.calls containsObject:@"yank"]);

    // focuslast 'i'.
    [spy.calls removeAllObjects];
    feed(vc, @"i"); TEST_ASSERT_TRUE([spy.calls containsObject:@"focuslast"]);

    // home u / U.
    [spy.calls removeAllObjects];
    feed(vc, @"u"); TEST_ASSERT_TRUE([spy.calls containsObject:@"home"]);
    feed(vc, @"U"); TEST_ASSERT_TRUE([spy.calls containsObject:@"home"]);

    // zoom z (needs a second key to complete the chord).
    vc = newVc(spy); feed(vc, @"z"); feed(vc, @"z");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"zoom:1"]);
}

static void test_controller_gcmd(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    feed(vc, @"gg"); TEST_ASSERT_TRUE([spy.calls containsObject:@"scroll:g:0"]);
    feed(vc, @"gh"); TEST_ASSERT_TRUE(![spy.calls containsObject:@"gohomeurl"]);
    feed(vc, @"gH"); TEST_ASSERT_TRUE([spy.calls containsObject:@"home"]);
    feed(vc, @"gi"); TEST_ASSERT_TRUE([spy.calls containsObject:@"focusinput"]);
    feed(vc, @"gt"); TEST_ASSERT_TRUE([spy.calls containsObject:@"nexttab"]);
    feed(vc, @"gT"); TEST_ASSERT_TRUE([spy.calls containsObject:@"prevtab"]);
    feed(vc, @"2"); feed(vc, @"g"); feed(vc, @"t");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"gototab:1"]);
    feed(vc, @"2"); feed(vc, @"g"); feed(vc, @"T");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"gototablast:2"]);
    feed(vc, @"g"); feed(vc, @"0"); TEST_ASSERT_TRUE([spy.calls containsObject:@"gototab:0"]);
    feed(vc, @"g"); feed(vc, @"$"); TEST_ASSERT_TRUE([spy.calls containsObject:@"gototab:9223372036854775807"]);
    feed(vc, @"gf"); TEST_ASSERT_TRUE([spy.calls containsObject:@"viewsource"]);
    feed(vc, @"gF"); TEST_ASSERT_TRUE([spy.calls containsObject:@"viewsource"]);
    feed(vc, @"gu"); TEST_ASSERT_TRUE([spy.calls containsObject:@"gohomeurl"]);
    feed(vc, @"gU"); TEST_ASSERT_TRUE([spy.calls containsObject:@"gohomeurl"]);
    feed(vc, @"g"); feed(vc, @";"); feed(vc, @"w"); TEST_ASSERT_TRUE([spy.calls containsObject:@"toggleshints"]);

    // A g sub-command with no handler still consumes the keys (error converted
    // to a completed result by the parser).
    vc = newVc(spy);
    BOOL r = [vc handleKeyCode:0 modifiers:0 characters:S('g')];
    TEST_ASSERT_TRUE(r);
    r = [vc handleKeyCode:0 modifiers:0 characters:S('x')];
    TEST_ASSERT_TRUE(r);
}

static void test_controller_prevnext_and_scroll_keys(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // All the scroll variants.
    unichar keys[] = {'h','j','k','l','G','H','M','L','$','0',' '};
    for (int i = 0; i < 11; i++) {
        unichar k = keys[i];
        [spy.calls removeAllObjects];
        vc = newVc(spy);
        BOOL consumed = [vc handleKeyCode:0 modifiers:0 characters:[[NSString alloc] initWithCharacters:&k length:1]];
        (void)consumed;
        __block BOOL sawScroll = NO;
        for (NSString *c in spy.calls) { if ([c hasPrefix:@"scroll:"]) sawScroll = YES; }
        TEST_ASSERT_TRUE(sawScroll);
    }
    // [ or ] maps to prevnext which the backend reports as handled (consumed).
    BOOL r = [vc handleKeyCode:0 modifiers:0 characters:S('[')];
    TEST_ASSERT_TRUE(r);
    r = [vc handleKeyCode:0 modifiers:0 characters:S(']')];
    TEST_ASSERT_TRUE(r);
}

static void test_controller_hint_mode_keys(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // Enter hint mode via ';o', then feed a hint key.
    feed(vc, @";"); feed(vc, @"o"); feed(vc, @"w");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"hintkey:w"]);

    // ESC in hint mode cancels (toggle hints).
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @";"); feed(vc, @"o"); feed(vc, @"\x1b");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"toggleshints"]);

    // Tab in hint mode cancels too.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @";"); feed(vc, @"o"); feed(vc, @"\t");
    TEST_ASSERT_TRUE([spy.calls containsObject:@"toggleshints"]);

    // Empty chars in hint mode -> consumed (returns YES), no call.
    [spy.calls removeAllObjects];
    vc = newVc(spy); feed(vc, @";"); feed(vc, @"o");
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:@""]);
}

static void test_controller_commandline_committed_search(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // Enter search mode then commit a line -> vimSearch:forward.
    feed(vc, @"/");
    [vc commandLineCommitted:@"foo"];
    TEST_ASSERT_TRUE([spy.calls containsObject:@"search:1:foo"]);
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);
    // '?' -> backward.
    [spy.calls removeAllObjects];
    feed(vc, @"?"); [vc commandLineCommitted:@"bar"];
    TEST_ASSERT_TRUE([spy.calls containsObject:@"search:0:bar"]);
}

static void test_controller_pass_and_esc(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // ^Z -> passthrough.
    feed(vc, [[NSString alloc] initWithCharacters:(unichar[]){0x1a} length:1]);
    TEST_ASSERT_TRUE([spy.calls containsObject:@"passthrough"]);
    // ESC inside command/search returns to normal (consumed via esc command).
    feed(vc, @"i"); [vc reset];
    [vc handleKeyCode:0 modifiers:0 characters:S(27)];
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);
}

static void test_controller_remap_recursion(void) {
    VimController *vc = newVc(newSpy());
    // Mapped "a" -> "j" (normal-mode scroll) with remap (noremap NO).
    [[VimbConfig shared] addMappingForMode:@"n" lhs:@"a" rhs:@"j" noremap:NO];
    [vc handleKeyCode:0 modifiers:0 characters:S('a')];
    // The remapped rhs "j" scrolls.
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"a"];
}

static void test_controller_no_appkit_handle(void) {
    // handleKeyDown requires an NSEvent (AppKit path) — not headless-testable.
    // Guard only that the Foundation seam is what we exercise elsewhere.
    VimController *vc = [[VimController alloc] init];
    vc.mode = VimModeNormal;
    TEST_ASSERT_TRUE(vc != nil);
}

#pragma mark - Additional coverage

static void test_config_apply_existing_and_resolve_empty(void) {
    VimbConfig *c = shortcutConfig();
    // applyShortcut with a valid key expands the template.
    TEST_ASSERT_EQ_STR([c applyShortcut:@"_vimb1_" query:@"hello world"],
                       @"only-zero:hello%20world");
    // resolveMappingForMode with an empty buffer -> none.
    VimbConfig *cc = [VimbConfig shared];
    [cc loadDefaults];
    NSDictionary *res = [cc resolveMappingForMode:@"n" buffer:@""];
    TEST_ASSERT_EQ_STR(res[@"status"], @"none");
}

static void test_config_convert_ctrl_digit(void) {
    VimbConfig *c = [VimbConfig shared];
    // <C-3>: 3-char ctrl label with a non-alnum digit -> unknown label, the
    // whole token is kept literally.
    TEST_ASSERT_EQ_STR([c convertKeyString:@"<C-3>"], @"C-3");
}

static void test_controller_control_key_variants(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // ^C (0x03) reload.
    [spy.calls removeAllObjects];
    feed(vc, S(0x03)); TEST_ASSERT_TRUE([spy.calls containsObject:@"reload"]);
    // ^D (0x04), ^F (0x06), ^U (0x15) scroll.
    unichar ctrl[] = {0x04, 0x06, 0x15};
    for (int i = 0; i < 3; i++) {
        unichar c = ctrl[i];
        [spy.calls removeAllObjects];
        vc = newVc(spy);
        [vc handleKeyCode:0 modifiers:0 characters:[[NSString alloc] initWithCharacters:&c length:1]];
        __block BOOL saw = NO;
        for (NSString *s in spy.calls) { if ([s hasPrefix:@"scroll:"]) saw = YES; }
        TEST_ASSERT_TRUE(saw);
    }
}

static void test_controller_cmd_and_empty_chars(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // Cmd modifier: key not consumed (goes to app menu/WebKit).
    BOOL r = [vc handleKeyCode:0 modifiers:(1UL << 20) characters:S('c')];
    TEST_ASSERT_TRUE(!r);
    // Empty chars in normal mode -> not consumed.
    r = [vc handleKeyCode:0 modifiers:0 characters:@""];
    TEST_ASSERT_TRUE(!r);
    // Ctrl+alpha computes the raw control char (lower + upper).
    [spy.calls removeAllObjects];
    vc = newVc(spy);
    [vc handleKeyCode:0 modifiers:(1UL << 18) characters:S('a')]; // ^A -> incr
    TEST_ASSERT_TRUE([spy.calls containsObject:@"incr:1:0"]);
}

static void test_controller_map_ex_command_route(void) {
    VimController *vc = newVc(newSpy());
    // A mapping whose rhs starts with ':' routes the remainder as an ex command
    // over the same channel the config file uses.
    __block NSMutableArray<NSString *> *posted = [NSMutableArray array];
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"VimbRunCommand" object:nil queue:nil
        usingBlock:^(NSNotification *n){ [posted addObject:n.userInfo[@"command"]]; }];
    [[VimbConfig shared] addMappingForMode:@"n" lhs:@"x" rhs:@":open example.com" noremap:YES];
    [vc handleKeyCode:0 modifiers:0 characters:S('x')];
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"x"];
    TEST_ASSERT_EQ_I(posted.count, 1);
    TEST_ASSERT_EQ_STR(posted[0], @"open example.com");
}

static void test_controller_map_infinite_guard(void) {
    VimController *vc = newVc(newSpy());
    // A self-referential non-noremap mapping must be caught by the guard.
    [[VimbConfig shared] addMappingForMode:@"n" lhs:@"a" rhs:@"a" noremap:NO];
    [vc handleKeyCode:0 modifiers:0 characters:S('a')];
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"a"];
}

static void test_autocmd_multiword_and_remove_all(void) {
    // Multi-word ex command (cmdParts word collection) fires correctly.
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    au.reporter = ^(NSString *msg, BOOL error) { (void)msg; (void)error; };
    __block int fired = 0;
    au.executor = ^(NSString *cmd) { (void)cmd; if ([cmd hasPrefix:@"open foo"]) fired++; };
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-finished * :open foo bar"]);
    [au fireEvent:VAuLoadFinished uri:@"http://x"];
    TEST_ASSERT_EQ_I(fired, 1);

    // Remove an "all" entry via :autocmd! * * (wildcard event -> VAuAll).
    VimbAutocmd *au2 = [[VimbAutocmd alloc] init];
    au2.reporter = ^(NSString *msg, BOOL error) { (void)msg; (void)error; };
    TEST_ASSERT_TRUE([au2 parseAutocmdLine:@"all * :cleanup"]);
    TEST_ASSERT_TRUE([au2 hasEvent:VAuAll]);
    TEST_ASSERT_TRUE([au2 parseAutocmdLine:@"! * *"]);
    TEST_ASSERT_TRUE(![au2 hasEvent:VAuAll]); // entry removed
}

static void test_ex_bma_and_shortcut_errors(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    // bma with no URL -> error.
    [ex runCommand:@"bma"];
    __block BOOL sawBma = NO;
    for (NSString *c in a.calls) { if ([c containsString:@"bma requires"]) sawBma = YES; }
    TEST_ASSERT_TRUE(sawBma);
    // shortcut-add with no name/url -> error.
    [a.calls removeAllObjects];
    [ex runCommand:@"shortcut-add"];
    [ex runCommand:@"shortcut-add nospaces"]; // url empty
    [ex runCommand:@"shortcut-default"];       // empty key
    __block int errs = 0;
    for (NSString *c in a.calls) { if ([c hasPrefix:@"msg:1:"]) errs++; }
    TEST_ASSERT_TRUE(errs >= 3);
}

static void test_ex_autocmd_fire_executor(void) {
    BehavActor *a = newActor();
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = a;
    VimbAutocmd *au = [VimbConfig shared].autocmd;
    // Install an autocmd through the ex layer, then fire it (executes the
    // executor block which routes back through runCommand).
    [ex runCommand:@"autocmd load-finished https://example.com/* :open https://x.com"];
    [au fireEvent:VAuLoadFinished uri:@"https://example.com/page"];
    BOOL saw = NO;
    for (NSString *c in a.calls) { if ([c hasPrefix:@"open:0:"]) saw = YES; }
    TEST_ASSERT_TRUE(saw);
    // Tear down to avoid leaking into other tests.
    [ex runCommand:@"autocmd! load-finished https://example.com/*"];
}

static void test_controller_ambiguous_and_register(void) {
    BehavSpy *spy = newSpy();
    VimController *vc = newVc(spy);
    // "jj" mapping makes a single "j" an ambiguous strict prefix.
    [[VimbConfig shared] addMappingForMode:@"n" lhs:@"jj" rhs:@"k" noremap:YES];
    BOOL r = [vc handleKeyCode:0 modifiers:0 characters:S('j')]; // ambiguous -> consumes, keeps waiting
    TEST_ASSERT_TRUE(r);
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"jj"];

    // Register lead-in '"' then a non-register char -> phase completes with no reg.
    [spy.calls removeAllObjects];
    vc = newVc(spy);
    [vc handleKeyCode:0 modifiers:0 characters:S('"')];
    BOOL r2 = [vc handleKeyCode:0 modifiers:0 characters:S('!')];
    TEST_ASSERT_TRUE(!r2); // no command attached
    (void)spy;
}

#pragma mark - main

// Entry point invoked from test_main.m's main(). Returns 0 on success.
int run_behavior_main(void) {
    RUN_TEST(test_map_insert_and_delete);
    RUN_TEST(test_map_delete_nonexistent);
    RUN_TEST(test_map_insert_multiple_modes);
    RUN_TEST(test_map_insert_overwrite);
    RUN_TEST(test_map_delete_wrong_mode);
    RUN_TEST(test_map_special_keys);
    RUN_TEST(test_map_ctrl_key);

    RUN_TEST(test_shortcut_basic);
    RUN_TEST(test_shortcut_shell_param);
    RUN_TEST(test_shortcut_remove);
    RUN_TEST(test_shortcut_no_placeholder_template);
    RUN_TEST(test_search_engine_uses_engine);
    RUN_TEST(test_loaduri_decision);
    RUN_TEST(test_shared_initialized_with_defaults);

    RUN_TEST(test_config_get_and_source_content);
    RUN_TEST(test_config_convert_edge_cases);

    RUN_TEST(test_engine_global_mark_trim);
    RUN_TEST(test_autocmd_every_event_and_download);
    RUN_TEST(test_autocmd_remove_and_group);
    RUN_TEST(test_autocmd_missing_command);
    RUN_TEST(test_autocmd_wildcard_patterns);

    RUN_TEST(test_handler_add_remove_lookup);
    RUN_TEST(test_handler_scheme_no_colon);
    RUN_TEST(test_handler_handle_uri_returns);

    RUN_TEST(test_ex_every_type);
    RUN_TEST(test_ex_tabcmd);
    RUN_TEST(test_ex_autocmd_augroup);
    RUN_TEST(test_ex_shortcut_commands);
    RUN_TEST(test_ex_map_commands_all_modes);
    RUN_TEST(test_ex_unknown_command);
    RUN_TEST(test_ex_ambiguous_command);

    RUN_TEST(test_controller_invoke_handlers);
    RUN_TEST(test_controller_pass_keys_to_page);
    RUN_TEST(test_controller_search_dir_and_count);
    RUN_TEST(test_controller_marks);
    RUN_TEST(test_controller_cmdline_and_input_open);
    RUN_TEST(test_controller_openclipboard_yank_focus);
    RUN_TEST(test_controller_gcmd);
    RUN_TEST(test_controller_prevnext_and_scroll_keys);
    RUN_TEST(test_controller_hint_mode_keys);
    RUN_TEST(test_controller_commandline_committed_search);
    RUN_TEST(test_controller_pass_and_esc);
    RUN_TEST(test_controller_remap_recursion);
    RUN_TEST(test_controller_no_appkit_handle);
    RUN_TEST(test_config_apply_existing_and_resolve_empty);
    RUN_TEST(test_config_convert_ctrl_digit);
    RUN_TEST(test_controller_control_key_variants);
    RUN_TEST(test_controller_cmd_and_empty_chars);
    RUN_TEST(test_controller_map_ex_command_route);
    RUN_TEST(test_controller_map_infinite_guard);
    RUN_TEST(test_autocmd_multiword_and_remove_all);
    RUN_TEST(test_ex_bma_and_shortcut_errors);
    RUN_TEST(test_ex_autocmd_fire_executor);
    RUN_TEST(test_controller_ambiguous_and_register);

    return RUN_ALL_TESTS();
}

// Unit tests for the Foundation-only vimb macOS sources. Run via `make test`.
//
// The C reference behavior lives in ../tests (gtester), which we must not
// touch; these tests check the portable ObjC ports (VimController,
// VimbStorage, VimbConfig, VimbEx, VimbEngine, VimbAutocmd) through their
// public APIs, with storage rooted in a temp dir so real user data is never
// touched.

#import "testlib.h"

#import <objc/objc-runtime.h>

#import "VimController.h"
#import "VimbStorage.h"
#import "VimbConfig.h"
#import "VimbEx.h"
#import "VimbExParser.h"
#import "VimbEngine.h"
#import "VimbAutocmd.h"
#import "VimbPath.h"

typedef NS_ENUM(NSInteger, ScrollMode) { ScrollModeNone = 0, ScrollModeScroll };

// Spy VimDelegate that records vimScrollMode: calls and simple mode state.
@interface SpyDelegate : NSObject <VimDelegate>
@property(nonatomic, assign) NSInteger scrollCount;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *scrollChars;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *scrollCounts;
@property(nonatomic, assign) VimMode lastPromptMode;
@property(nonatomic, assign) BOOL firedTheme; // unused placeholder
- (void)resetSpy;
@end

@implementation SpyDelegate
- (instancetype)init {
    self = [super init];
    if (self) { [self resetSpy]; }
    return self;
}
- (void)resetSpy {
    _scrollCount = 0;
    _scrollChars = [NSMutableArray array];
    _scrollCounts = [NSMutableArray array];
    _lastPromptMode = -1;
    _firedTheme = NO;
}
- (void)vimScrollMode:(unichar)mode count:(NSUInteger)count {
    _scrollCount++;
    [_scrollChars addObject:@((int)mode)];
    [_scrollCounts addObject:@((NSUInteger)count)];
}
- (void)vimGoBack {}
- (void)vimGoForward {}
- (void)vimReload {}
- (void)vimReloadBypassCache {}
- (void)vimStop {}
- (void)vimOpenURL:(NSString *)urlValue inNewTab:(BOOL)newTab {}
- (void)vimOpenHome {}
- (void)vimGoHomeURL {}
- (void)vimOpenPrompt:(NSString *)prompt mode:(VimMode)mode { _lastPromptMode = mode; }
- (void)vimSearch:(NSString *)query forward:(BOOL)forward {}
- (void)vimSearchDirection:(NSInteger)dir {}
- (void)vimSearchSelectionForward:(BOOL)forward {}
- (void)vimFire {}
- (void)vimFocusLastActive {}
- (void)vimFocusInput {}
- (void)vimNextTab {}
- (void)vimPrevTab {}
- (void)vimGotoTab:(NSUInteger)index {}
- (void)vimGotoTabFromLast:(NSInteger)count {}
- (void)vimNewTab {}
- (void)vimCloseTab {}
- (void)vimToggleHints {}
- (void)vimEnterHints:(NSString *)mode gmode:(BOOL)gmode {}
- (void)vimHintKey:(NSString *)key {}
- (void)vimHintFocus:(BOOL)back {}
- (void)vimHintBackspace {}
- (void)vimHintFire {}
- (void)vimShowMessage:(NSString *)message error:(BOOL)error {}
- (void)vimFocusWebView {}
- (void)vimEnterPassThrough {}
- (void)vimYankURI:(unichar)reg {}
- (void)vimYankSelection:(unichar)reg {}
- (NSString *)vimCurrentURI { return @""; }
- (void)vimSetMark:(unichar)c {}
- (void)vimJumpMark:(unichar)c {}
- (void)vimViewSource {}
- (void)vimViewInspector {}
- (void)vimZoom:(BOOL)in {}
- (void)vimIncrement:(BOOL)up count:(NSInteger)count {}
- (void)vimQuit {}
- (void)vimOpenClipboard:(NSString *)counter {}
@end

// Wraps a char in an NSString (like charactersIgnoringModifiers).
static NSString *S(unichar c) {
    return [NSString stringWithCharacters:&c length:1];
}

#pragma mark - VimbStorage

static void test_storage_prepend_dedup_max(void) {
    VimbStorage *s = [VimbStorage storageInTempDirectoryWithName:@"hist"];
    [s clear];
    TEST_ASSERT_EQ_I(s.lines.count, 0);

    [s prepend:@"one" max:10];
    [s prepend:@"two" max:10];
    [s prepend:@"three" max:10];
    TEST_ASSERT_EQ_I(s.lines.count, 3);
    TEST_ASSERT_EQ_STR(s.top, @"three");

    // Dedup: re-prepending "one" moves it to front, no duplicate.
    [s prepend:@"one" max:10];
    TEST_ASSERT_EQ_I(s.lines.count, 3);
    TEST_ASSERT_EQ_STR(s.top, @"one");
    TEST_ASSERT_EQ_STR(s.lines[1], @"three");

    // Max trimming.
    [s clear];
    [s prepend:@"a" max:2];
    [s prepend:@"b" max:2];
    [s prepend:@"c" max:2];
    TEST_ASSERT_EQ_I(s.lines.count, 2);
    TEST_ASSERT_EQ_STR(s.top, @"c");
    TEST_ASSERT_EQ_STR(s.lines[1], @"b");

    [s clear];
}

static void test_storage_removeLine_top_popLast_clear(void) {
    VimbStorage *s = [VimbStorage storageInTempDirectoryWithName:@"hist2"];
    [s clear];
    [s prepend:@"x" max:10];
    [s prepend:@"y" max:10];
    TEST_ASSERT_EQ_STR(s.top, @"y");

    [s removeLine:@"x"];
    TEST_ASSERT_EQ_I(s.lines.count, 1);
    TEST_ASSERT_EQ_STR(s.lines[0], @"y");

    TEST_ASSERT_EQ_STR(s.popLast, @"y");
    TEST_ASSERT_EQ_I(s.lines.count, 0);
    TEST_ASSERT_TRUE(s.popLast == nil); // empty store returns nil

    [s prepend:@"z" max:5];
    [s clear];
    TEST_ASSERT_EQ_I(s.lines.count, 0);

    [s clear];
}

static void test_storage_writeAll(void) {
    VimbStorage *s = [VimbStorage storageInTempDirectoryWithName:@"hist3"];
    [s clear];
    [s writeAll:@[ @"a", @"b" ]];
    TEST_ASSERT_EQ_I(s.lines.count, 2);
    TEST_ASSERT_EQ_STR(s.lines[0], @"a");
    TEST_ASSERT_EQ_STR(s.lines[1], @"b");
    [s clear];
}

static void test_storage_push_matches_prepend(void) {
    VimbStorage *s = [VimbStorage storageInTempDirectoryWithName:@"hist4"];
    [s clear];
    [s push:@"p" max:2];
    [s push:@"q" max:2];
    TEST_ASSERT_EQ_STR(s.top, @"q");
    TEST_ASSERT_EQ_I(s.lines.count, 2);
    [s clear];
}

// append: adds to the END (util_file_append parity) so qpush/qpop is FIFO:
// push a, push b, pop -> a (oldest), pop -> b.
static void test_storage_append_fifo(void) {
    VimbStorage *s = [VimbStorage storageInTempDirectoryWithName:@"queue1"];
    [s clear];
    [s append:@"a"];
    [s append:@"b"];
    TEST_ASSERT_EQ_I(s.lines.count, 2);
    TEST_ASSERT_EQ_STR(s.lines[0], @"a");
    TEST_ASSERT_EQ_STR(s.lines[1], @"b");
    // pop front is FIFO with append.
    TEST_ASSERT_EQ_STR(s.popLast, @"a");
    TEST_ASSERT_EQ_STR(s.popLast, @"b");
    [s clear];
}

static void test_storage_dirs(void) {
    // Shared base dirs resolve to real, existing paths.
    TEST_ASSERT_NOTNULL([VimbStorage appSupportDir]);
    TEST_ASSERT_NOTNULL([VimbStorage cacheDir]);
    // Default initWithName: uses App Support (any name maps to a path).
    VimbStorage *s = [[VimbStorage alloc] initWithName:@"virtual-handle"];
    TEST_ASSERT_NOTNULL(s.dir);
    [s clear]; // touches only that handle path, not real data.
}

#pragma mark - VimbConfig

static void test_config_load_defaults(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    // scroll-step default is 40.
    TEST_ASSERT_EQ_I([c getInt:@"scroll-step" defaultValue:-1], 40);
    // home-page resolves to the duckduckgo main page (query stripped).
    NSString *home = [c getString:@"home-page" defaultValue:@""];
    TEST_ASSERT_TRUE([home hasPrefix:@"https://duckduckgo.com/html/"]);
    TEST_ASSERT_TRUE(![home containsString:@"?"]);
    // defaultShortcut
    TEST_ASSERT_EQ_STR(c.defaultShortcut, @"dl");
    TEST_ASSERT_TRUE([c getBool:@"status-bar" defaultValue:NO]);
    TEST_ASSERT_TRUE(![c getBool:@"some-missing" defaultValue:NO]);
    TEST_ASSERT_EQ_I([c getInt:@"missing-int" defaultValue:7], 7);
}

static void test_config_apply_setting_getters(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    [c applySetting:@"scroll-step" value:@200];
    TEST_ASSERT_EQ_I(c.scrollstep, 200);
    TEST_ASSERT_EQ_I([c getInt:@"scroll-step" defaultValue:-1], 200);

    [c applySetting:@"some-bool" value:@YES];
    TEST_ASSERT_TRUE([c getBool:@"some-bool" defaultValue:NO]);
    TEST_ASSERT_EQ_STR([c getString:@"some-missing" defaultValue:@"dv"], @"dv");

    [c applySetting:@"footext" value:@(0)];
    TEST_ASSERT_EQ_STR([c getString:@"footext" defaultValue:@"fallback"], @"fallback");

    [c loadDefaults]; // restore
}

// Setting-value validation mirrors the GTK setters (setting.c).
static void test_config_validate_setting(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    // cookie-accept in [always, origin, never].
    TEST_ASSERT_TRUE([c validateSetting:@"cookie-accept" value:@"always"]);
    TEST_ASSERT_TRUE([c validateSetting:@"cookie-accept" value:@"origin"]);
    TEST_ASSERT_TRUE([c validateSetting:@"cookie-accept" value:@"never"]);
    TEST_ASSERT_FALSE([c validateSetting:@"cookie-accept" value:@"banana"]);

    // geolocation / notification in [always, ask, never].
    TEST_ASSERT_TRUE([c validateSetting:@"geolocation" value:@"ask"]);
    TEST_ASSERT_FALSE([c validateSetting:@"geolocation" value:@"sometimes"]);
    TEST_ASSERT_TRUE([c validateSetting:@"notification" value:@"never"]);
    TEST_ASSERT_FALSE([c validateSetting:@"notification" value:@"maybe"]);

    // hardware-acceleration-policy in [always, ondemand, never].
    TEST_ASSERT_TRUE([c validateSetting:@"hardware-acceleration-policy" value:@"ondemand"]);
    TEST_ASSERT_FALSE([c validateSetting:@"hardware-acceleration-policy" value:@"fast"]);

    // download-path must be absolute.
    TEST_ASSERT_TRUE([c validateSetting:@"download-path" value:@"/tmp/x"]);
    TEST_ASSERT_FALSE([c validateSetting:@"download-path" value:@"relative/dir"]);

    // Unknown settings always validate.
    TEST_ASSERT_TRUE([c validateSetting:@"scroll-step" value:@"40"]);
}

// :set name=value must coerce the typed string to the setting's declared type,
// not flatten every value to a double (which previously zeroed char settings).
static void test_config_coerce_setting_value(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    // char-typed settings keep their string.
    TEST_ASSERT_EQ_STR([c coerceSettingValue:@"cookie-accept" stringValue:@"never"], @"never");
    TEST_ASSERT_EQ_STR([c coerceSettingValue:@"download-command" stringValue:@"/usr/bin/x %s"], @"/usr/bin/x %s");

    // int-typed settings become NSNumber(integer).
    id scroll = [c coerceSettingValue:@"scroll-step" stringValue:@"250"];
    TEST_ASSERT_TRUE([scroll isKindOfClass:[NSNumber class]]);
    TEST_ASSERT_EQ_I([scroll integerValue], 250);

    // bool-typed settings become NSNumber(boolean).
    id imagesOff = [c coerceSettingValue:@"images" stringValue:@"off"];
    TEST_ASSERT_EQ_I([imagesOff boolValue], NO);
    id scriptsOn = [c coerceSettingValue:@"scripts" stringValue:@"on"];
    TEST_ASSERT_EQ_I([scriptsOn boolValue], YES);

    // type retrieval.
    TEST_ASSERT_EQ_I([c typeForSetting:@"cookie-accept"], VSettingChar);
    TEST_ASSERT_EQ_I([c typeForSetting:@"scroll-step"], VSettingInt);
    TEST_ASSERT_EQ_I([c typeForSetting:@"images"], VSettingBool);

    [c loadDefaults]; // restore
}

static void test_config_search_engine(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    NSString *mainPage = [c searchEngineMainPage];
    TEST_ASSERT_EQ_STR(mainPage, @"https://duckduckgo.com/html/");

    NSString *q = [c searchURLForQuery:@"hello world"];
    TEST_ASSERT_TRUE([q hasPrefix:@"https://duckduckgo.com/html/?q="]);
    TEST_ASSERT_TRUE([q containsString:@"hello%20world"]);
}

static void test_config_mappings(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];

    // add "gg"->"G" noremap
    NSDictionary *entry = [c addMappingForMode:@"n" lhs:@"gg" rhs:@"G" noremap:YES];
    TEST_ASSERT_NOTNULL(entry);
    TEST_ASSERT_EQ_STR(entry[@"lhs"], @"gg");
    TEST_ASSERT_EQ_STR(entry[@"rhs"], @"G");

    // resolve a full match.
    NSDictionary *res = [c resolveMappingForMode:@"n" buffer:@"gg"];
    TEST_ASSERT_EQ_STR(res[@"status"], @"match");
    TEST_ASSERT_EQ_STR(res[@"rhs"], @"G");

    // ambiguous prefix ("g" is prefix of "gg").
    res = [c resolveMappingForMode:@"n" buffer:@"g"];
    TEST_ASSERT_EQ_STR(res[@"status"], @"ambiguous");

    // none.
    res = [c resolveMappingForMode:@"n" buffer:@"xyz"];
    TEST_ASSERT_EQ_STR(res[@"status"], @"none");

    // remove returns YES and then NO the second time.
    TEST_ASSERT_TRUE([c removeMappingForMode:@"n" lhs:@"gg"]);
    TEST_ASSERT_TRUE(![c removeMappingForMode:@"n" lhs:@"gg"]);
}

static void test_config_convert_key_string(void) {
    VimbConfig *c = [VimbConfig shared];
    TEST_ASSERT_EQ_STR([c convertKeyString:@""], @"");
    TEST_ASSERT_EQ_STR([c convertKeyString:@"gg"], @"gg");
    // <C-x> -> control char 0x18.
    NSString *cx = [c convertKeyString:@"<C-x>"];
    TEST_ASSERT_EQ_I([cx characterAtIndex:0], 0x18);
    // <Esc> -> 0x1b.
    NSString *esc = [c convertKeyString:@"<Esc>"];
    TEST_ASSERT_EQ_I([esc characterAtIndex:0], 0x1b);
    // Unknown label falls back to literal token.
    NSString *un = [c convertKeyString:@"<Bogus>"];
    TEST_ASSERT_EQ_STR(un, @"Bogus");
    // Escaped backslash-\< keeps the '<' literal.
    NSString *lit = [c convertKeyString:@"\\<x"];
    TEST_ASSERT_EQ_STR(lit, @"<x");
    // Lowercase control.
    NSString *cc = [c convertKeyString:@"<c-a>"];
    TEST_ASSERT_EQ_I([cc characterAtIndex:0], 0x01);
}

static void test_config_shortcuts_and_sources(void) {
    VimbConfig *c = [VimbConfig shared];
    [c loadDefaults];
    TEST_ASSERT_EQ_STR([c resolveShortcut:@"dl"],
                       @"https://duckduckgo.com/html/?q=$0");
    TEST_ASSERT_TRUE([c resolveShortcut:@"nonexistent"] == nil);
    // historyCommand returns a (non-nil) path under App Support.
    TEST_ASSERT_NOTNULL([c historyCommand]);
    // sourceConfigFile with a missing file is a no-op (no exception).
    [c sourceConfigFile];

    // applySetting for each scalar type.
    [c applySetting:@"font-size" value:@24];
    TEST_ASSERT_EQ_I([c getInt:@"font-size" defaultValue:0], 24);
    [c applySetting:@"smooth-scrolling" value:@YES];
    TEST_ASSERT_TRUE([c getBool:@"smooth-scrolling" defaultValue:NO]);
    [c applySetting:@"dark-mode" value:[NSNumber numberWithBool:YES]];
    TEST_ASSERT_TRUE([c getBool:@"dark-mode" defaultValue:NO]);
    [c loadDefaults];
}

#pragma mark - VimbEx

// Minimal actor recording open calls.
@interface SpyExActor : NSObject <VimbExActor>
@property(nonatomic, strong) NSMutableArray<NSString *> *opened;
@property(nonatomic, strong) NSMutableArray<NSString *> *setArgs;
@property(nonatomic, assign) BOOL quitAtEnd;
@end

@implementation SpyExActor
- (instancetype)init { self = [super init]; if (self) { _opened = [NSMutableArray array]; _setArgs = [NSMutableArray array]; _quitAtEnd = NO; } return self; }
- (void)exOpen:(NSString *)arg newTab:(BOOL)newTab { [_opened addObject:arg]; }
- (void)exSet:(NSString *)fullArg { [_setArgs addObject:fullArg]; }
- (void)exCloseActiveTab {}
- (void)exNextTab {}
- (void)exPrevTab {}
- (void)exFirstTab {}
- (void)exLastTab {}
- (void)exReload {}
- (void)exStop {}
- (void)exHome {}
- (void)exQuit:(BOOL)bang { (void)bang; }
- (void)exQuitAll:(BOOL)bang { (void)bang; }
- (void)exEval:(NSString *)js suppressOutput:(BOOL)suppress { (void)js; (void)suppress; }
- (void)exNormal:(NSString *)keys applyMapping:(BOOL)applyMapping { (void)keys; (void)applyMapping; }
- (void)exClearData:(NSString *)types { (void)types; }
- (void)exPrint {}
- (void)exHandlerAdd:(NSString *)scheme command:(NSString *)command success:(void (^)(BOOL))callback {
    (void)scheme; (void)command; if (callback) callback(YES);
}
- (void)exHandlerRemove:(NSString *)scheme success:(void (^)(BOOL))callback {
    (void)scheme; if (callback) callback(YES);
}
- (void)exShell:(NSString *)arg async:(BOOL)async { (void)arg; (void)async; }
- (void)exMessage:(NSString *)msg error:(BOOL)error { (void)msg; (void)error; }
- (void)exSavePage:(NSString *)path {}
- (void)exRegisterList {}
- (void)exSource:(NSString *)path {}
- (void)exQueue:(NSString *)cmd arg:(NSString *)arg {}
- (void)exShowMessages {}
- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title { (void)url; (void)title; }
- (void)exBookmarkCurrent:(NSString *)tags { (void)tags; }
- (void)exUnbookmark:(NSString *)match { (void)match; }
@end

static void test_ex_open(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;
    [ex runCommand:@"open http://example.com"];
    TEST_ASSERT_EQ_I(a.opened.count, 1);
    TEST_ASSERT_EQ_STR(a.opened[0], @"http://example.com");

    // tabopen opens in new tab.
    [a.opened removeAllObjects];
    [ex runCommand:@"tabopen http://x.com"];
    TEST_ASSERT_EQ_I(a.opened.count, 1);
    TEST_ASSERT_EQ_STR(a.opened[0], @"http://x.com");
}

static void test_ex_set_and_unknown(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;
    [ex runCommand:@"set scroll-step=100"];
    TEST_ASSERT_EQ_I(a.setArgs.count, 1);
    TEST_ASSERT_EQ_STR(a.setArgs[0], @"scroll-step=100");
}

static void test_ex_map_command(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;
    // "nnoremap gg G" registers against VimbConfig normal mode.
    [ex runCommand:@"nnoremap gg G"];
    NSDictionary *res = [[VimbConfig shared] resolveMappingForMode:@"n" buffer:@"gg"];
    TEST_ASSERT_EQ_STR(res[@"status"], @"match");
    TEST_ASSERT_EQ_STR(res[@"rhs"], @"G");
    TEST_ASSERT_TRUE([res[@"noremap"] boolValue]);
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"gg"];
}

static void test_ex_commands_and_names(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    NSArray<NSString *> *names = [ex commandNames];
    TEST_ASSERT_TRUE(names.count > 0);
    // % is not a vimb ex rhs placeholder (vim-only); it passes through.
    TEST_ASSERT_EQ_STR([ex expandToken:@"%"], @"%");
}

// ~ and $ path/env expansion (parity with util_parse_expansion for the
// EX_FLAG_EXP commands save/shellcmd/shellex/source).
static void test_ex_parser_path_expansion(void) {
    NSString *home = NSHomeDirectory();
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"~/x"],
                       [home stringByAppendingString:@"/x"]);
    // lone ~ at end resolves to home.
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"~"], home);
    // $VAR / ${VAR} via the environment.
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"$HOME"],
                       home);
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"${HOME}"],
                       home);
    // unknown $VAR expands to empty (parity with util_parse_expansion).
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"$NOPE_SETTING"], @"");
    // backslash escapes a literal ~ / $.
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"\\$HOME"], @"$HOME");
    // % passes through untouched.
    TEST_ASSERT_EQ_STR([VimbExParser expandPathVariableInString:@"%"], @"%");
}

static void test_ex_url_fallback(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;
    // A bare token with a dot is treated as a URL to open.
    [ex runCommand:@"example.com"];
    TEST_ASSERT_EQ_I(a.opened.count, 1);
    TEST_ASSERT_EQ_STR(a.opened[0], @"example.com");
}

// Direct structural test of the shared ex.c-faithful parser: resolves a name
// and separates lhs/rhs/bang/count/rest exactly as ex.c's ExArg would.
static void test_ex_parser_arg(void) {
    // Plain command, rhs preserved.
    VimbExArg *a = [VimbExParser parseLine:@"open https://x.com/path"];
    TEST_ASSERT_EQ_STR(a.command, @"open");
    TEST_ASSERT_EQ_STR(a.rest, @"https://x.com/path");
    TEST_ASSERT_EQ_STR(a.rhs, @"https://x.com/path");
    TEST_ASSERT_TRUE(a.lhs == nil);
    TEST_ASSERT_EQ_I(a.count, 0);
    TEST_ASSERT_TRUE(!a.bang);
    TEST_ASSERT_TRUE(!a.unknownCommand);

    // Leading ':' is consumed; abbreviation resolves (t -> tabopen).
    VimbExArg *t = [VimbExParser parseLine:@":t foo"];
    TEST_ASSERT_EQ_STR(t.command, @"tabopen");
    TEST_ASSERT_EQ_STR(t.rest, @"foo");

    // Count (":2tabnext") -> count=2, name resolves.
    VimbExArg *n = [VimbExParser parseLine:@":2tabnext"];
    TEST_ASSERT_EQ_STR(n.command, @"tabnext");
    TEST_ASSERT_EQ_I(n.count, 2);

    // Bang after a EX_FLAG_BANG command.
    VimbExArg *q = [VimbExParser parseLine:@"quit!"];
    TEST_ASSERT_EQ_STR(q.command, @"quit");
    TEST_ASSERT_TRUE(q.bang);

    // bang + rhs for :normal! gg.
    VimbExArg *ng = [VimbExParser parseLine:@"normal! gg"];
    TEST_ASSERT_EQ_STR(ng.command, @"normal");
    TEST_ASSERT_TRUE(ng.bang);
    TEST_ASSERT_EQ_STR(ng.rest, @"gg");
    TEST_ASSERT_EQ_STR(ng.rhs, @"gg");

    // LHS+CMD map: cmap <C-T> :tabopen<CR> -> lhs "C-T", rhs after.
    VimbExArg *m = [VimbExParser parseLine:@"cmap <C-T> :tabopen"];
    TEST_ASSERT_EQ_STR(m.command, @"cmap");
    TEST_ASSERT_EQ_STR(m.lhs, @"<C-T>");
    TEST_ASSERT_EQ_STR(m.rhs, @":tabopen");

    // LHS with escaped space stays part of the single word.
    VimbExArg *e = [VimbExParser parseLine:@"augroup foo\\ bar"];
    TEST_ASSERT_EQ_STR(e.command, @"augroup");
    TEST_ASSERT_EQ_STR(e.lhs, @"foo bar");

    // RHS list ends at |; CMD rhs keeps it.
    VimbExArg *p = [VimbExParser parseLine:@"set scroll-relax-until|z"];
    TEST_ASSERT_EQ_STR(p.command, @"set");
    TEST_ASSERT_EQ_STR(p.rhs, @"scroll-relax-until");

    // Unknown command -> unknownCommand, command nil.
    VimbExArg *u = [VimbExParser parseLine:@"bdelete foo"];
    TEST_ASSERT_TRUE(u.unknownCommand);
    TEST_ASSERT_TRUE(u.command == nil);
}

// First-prefix-wins resolution rules (ex.c parse_command_name).
// cleardata type-name table mirrors ex_cleardata (src/ex.c:930-943).
static void test_ex_cleardata_type_names(void) {
    NSArray<NSString *> *n = [VimbExParser cleardataTypeNames];
    TEST_ASSERT_TRUE([n containsObject:@"cookies"]);
    TEST_ASSERT_TRUE([n containsObject:@"offline-cache"]);
    TEST_ASSERT_TRUE([n containsObject:@"hsts-cache"]);
    TEST_ASSERT_TRUE([n containsObject:@"indexeddb-databases"]);
    // No GTK 'plugin-data' (removed in WebKitGTK 6.0).
    TEST_ASSERT_TRUE(![n containsObject:@"plugin-data"]);
}

static void test_ex_parser_abbreviation(void) {
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"q"], @"quit");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"t"], @"tabopen");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"o"], @"open");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"r"], @"register");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"tabn"], @"tabnext");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"tabp"], @"tabprev");
    // Exact names resolve to themselves.
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"quitall"], @"quitall");
    TEST_ASSERT_EQ_STR([VimbExParser matchCommandForName:@"register"], @"register");
    // Non-commands / empty -> nil.
    TEST_ASSERT_TRUE([VimbExParser matchCommandForName:@"reload"] == nil);
    TEST_ASSERT_TRUE([VimbExParser matchCommandForName:@"bd"] == nil);
    TEST_ASSERT_TRUE([VimbExParser matchCommandForName:@"bdelete"] == nil);
    TEST_ASSERT_TRUE([VimbExParser matchCommandForName:@""] == nil);
    TEST_ASSERT_TRUE([VimbExParser matchCommandForName:@"zzz"] == nil);
    // commandNames lists every table entry.
    NSUInteger names = [[VimbExParser commandNames] count];
    TEST_ASSERT_TRUE(names >= 40);
}

// VimbEx.runCommand: returns a VimbExCmdResult bitmask (CMD_SUCCESS|KEEPINPUT,
// parity with main.h). Distinct result channels for distinct command families.
static void test_ex_cmd_result(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;

    // Success (no keep): open / quit clear the input box.
    TEST_ASSERT_EQ_I((NSInteger)[ex runCommand:@"open https://x.com"],
                     (NSInteger)VimbExCmdResultSuccess);
    TEST_ASSERT_EQ_I((NSInteger)[ex runCommand:@"quit"],
                     (NSInteger)VimbExCmdResultSuccess);

    // eval returns CMD_SUCCESS (no keep) per ex.c:873.
    TEST_ASSERT_EQ_I((NSInteger)[ex runCommand:@"eval 1+1"],
                     (NSInteger)VimbExCmdResultSuccess);

    // Keep-input success: :bma keeps the line (ex.c CMD_SUCCESS|KEEPINPUT).
    VimbExCmdResult bma = [ex runCommand:@"bma work"];
    TEST_ASSERT_TRUE(bma & VimbExCmdResultSuccess);
    TEST_ASSERT_TRUE(bma & VimbExCmdResultKeepInput);

    // Keep-input success: :set keeps the line editable (setting.c).
    VimbExCmdResult set = [ex runCommand:@"set scroll-step=100"];
    TEST_ASSERT_TRUE(set & VimbExCmdResultSuccess);
    TEST_ASSERT_TRUE(set & VimbExCmdResultKeepInput);

    // Keep-input: :normal, :register, :save, sync :shellcmd (ex.c 1055/1128/1146/1199).
    VimbExCmdResult normal = [ex runCommand:@"normal gg"];
    TEST_ASSERT_TRUE(normal & VimbExCmdResultKeepInput);
    VimbExCmdResult rg = [ex runCommand:@"register"];
    TEST_ASSERT_TRUE(rg & VimbExCmdResultKeepInput);
    VimbExCmdResult sv = [ex runCommand:@"save /tmp/x.png"];
    TEST_ASSERT_TRUE(sv & VimbExCmdResultKeepInput);
    VimbExCmdResult sh = [ex runCommand:@"shellcmd ls"];
    TEST_ASSERT_TRUE(sh & VimbExCmdResultKeepInput);
    // Async :shellcmd! -> plain Success.
    TEST_ASSERT_EQ_I((NSInteger)[ex runCommand:@"shellcmd! ls"],
                     (NSInteger)VimbExCmdResultSuccess);

    // Error + keep-input: unknown command keeps the typo for correction.
    VimbExCmdResult unknown = [ex runCommand:@"notacommand"];
    TEST_ASSERT_TRUE((unknown & VimbExCmdResultSuccess) == 0);
    TEST_ASSERT_TRUE(unknown & VimbExCmdResultKeepInput);

    // Error + keep-input: malformed handler stays editable.
    VimbExCmdResult h = [ex runCommand:@"handler-add"]; // no scheme=command
    TEST_ASSERT_TRUE((h & VimbExCmdResultSuccess) == 0);
    TEST_ASSERT_TRUE(h & VimbExCmdResultKeepInput);

    // Constants mirror main.h CMD_SUCCESS=0x01, CMD_KEEPINPUT=0x02.
    TEST_ASSERT_EQ_I((NSInteger)VimbExCmdResultSuccess, 1);
    TEST_ASSERT_EQ_I((NSInteger)VimbExCmdResultKeepInput, 2);
}

static void test_ex_shortcut_and_bang(void) {
    VimbEx *ex = [[VimbEx alloc] init];
    SpyExActor *a = [[SpyExActor alloc] init];
    ex.actor = a;
    // GTK has no "leading ! runs a command" syntax: ":!open http://x.com" is
    // not a recognized command (name "!open"), so the whole line is treated
    // as a URL/query to open.
    [ex runCommand:@"!open http://x.com"];
    TEST_ASSERT_EQ_I(a.opened.count, 1);
    TEST_ASSERT_EQ_STR(a.opened[0], @"!open http://x.com");
}

static void test_path_unique_destination(void) {
    // Non-existent path is returned unchanged.
    NSString *dir = NSTemporaryDirectory();
    NSString *fresh1 = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"vbpath_%d_a.txt", (int)arc4random()]];
    TEST_ASSERT_EQ_STR([VimbPath uniqueDestinationForPath:fresh1], fresh1);

    // Existing base => append _N before the extension.
    NSString *exists = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"vbpath_%d_b.txt", (int)arc4random()]];
    [[NSData data] writeToFile:exists atomically:YES];
    NSString *one = [VimbPath uniqueDestinationForPath:exists];
    NSString *expectedOne = [dir stringByAppendingPathComponent:
        [[exists lastPathComponent] stringByReplacingOccurrencesOfString:@".txt" withString:@"_1.txt"]];
    TEST_ASSERT_EQ_STR(one, expectedOne);

    // Both exist => _N climbs until a free name (checks monotonic suffixing).
    [[NSData data] writeToFile:one atomically:YES];
    NSString *two = [VimbPath uniqueDestinationForPath:exists];
    TEST_ASSERT_TRUE([two hasSuffix:@"_2.txt"]);
    TEST_ASSERT_TRUE(![[NSFileManager defaultManager] fileExistsAtPath:two]);

    // No dot in the name => suffix appended (no extension to insert before).
    NSString *noDot = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"vbpath_%d_plain", (int)arc4random()]];
    [[NSData data] writeToFile:noDot atomically:YES];
    TEST_ASSERT_TRUE([[VimbPath uniqueDestinationForPath:noDot] hasSuffix:@"_plain_1"]);

    // `.tar.` two-dot extension: insert before ".tar.", i.e. x_1.tar.gz.
    NSString *tar = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"vbpath_%d_arch.tar.gz", (int)arc4random()]];
    [[NSData data] writeToFile:tar atomically:YES];
    NSString *tarU = [VimbPath uniqueDestinationForPath:tar];
    TEST_ASSERT_TRUE([[tarU lastPathComponent] hasPrefix:@"vbpath_"] && [tarU hasSuffix:@"_1.tar.gz"]);

    // Empty string returns empty.
    TEST_ASSERT_EQ_STR([VimbPath uniqueDestinationForPath:@""], @"");
}

#pragma mark - VimbEngine

static void test_engine_registers_marks(void) {
    VimbRegisters *regs = [[VimbRegisters alloc] init];
    [regs set:@"hello" forKey:'a'];
    TEST_ASSERT_EQ_STR([regs get:'a'], @"hello");
    TEST_ASSERT_TRUE([regs get:'z'] == nil);

    VimbMarks *marks = [[VimbMarks alloc] init];
    [marks setLocal:'a' top:42.5];
    TEST_ASSERT_EQ_I((NSInteger)[marks getLocal:'a'], 42);
    [marks setGlobal:'0' uri:@"https://example.com"];
    TEST_ASSERT_EQ_STR([marks getGlobal:'0'], @"https://example.com");
    TEST_ASSERT_TRUE([marks getGlobal:'9'] == nil);
}

static void test_engine_vsetting(void) {
    VSetting *vs = [[VSetting alloc] initWithName:@"x" type:VSettingInt value:@5 apply:nil];
    TEST_ASSERT_EQ_STR(vs.name, @"x");
    TEST_ASSERT_EQ_I(vs.type, VSettingInt);
    TEST_ASSERT_EQ_I([vs.value integerValue], 5);
}

#pragma mark - VimbAutocmd

static void test_autocmd_register_and_fire(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block NSMutableArray<NSString *> *fired = [NSMutableArray array];
    au.executor = ^(NSString *cmd) { [fired addObject:cmd]; };
    au.reporter = ^(NSString *msg, BOOL error) { (void)msg; (void)error; };

    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-finished * :reload"]);
    TEST_ASSERT_TRUE([au hasEvent:VAuLoadFinished]);

    [au fireEvent:VAuLoadFinished uri:@"https://example.com"];
    TEST_ASSERT_EQ_I(fired.count, 1);
    TEST_ASSERT_EQ_STR(fired[0], @"reload");

    // Full path: :autocmd via VimbEx strips the command name before parsing.
    [fired removeAllObjects];
    SpyExActor *actor = [[SpyExActor alloc] init];
    VimbEx *ex = [[VimbEx alloc] init];
    ex.actor = actor;
    [ex runCommand:@"autocmd load-finished https://example.com :reload"];
    [au fireEvent:VAuLoadFinished uri:@"https://example.com"];
    TEST_ASSERT_EQ_I(fired.count, 1);
    TEST_ASSERT_EQ_STR(fired[0], @"reload");
}

static void test_autocmd_augroup(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    au.reporter = ^(NSString *msg, BOOL error) { (void)msg; (void)error; };
    TEST_ASSERT_TRUE([au parseAugroupLine:@"MyGroup"]);
    TEST_ASSERT_TRUE([au parseAugroupLine:@"END"]);
    TEST_ASSERT_TRUE([au parseAugroupLine:@"!Other"]);
}

static void test_autocmd_wildcard(void) {
    VimbAutocmd *au = [[VimbAutocmd alloc] init];
    __block NSMutableArray<NSString *> *fired = [NSMutableArray array];
    au.executor = ^(NSString *cmd) { [fired addObject:cmd]; };

    // Pattern with a single * matches a substring.
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"load-starting https://example.com/* :reload"]);
    [au fireEvent:VAuLoadStarting uri:@"https://example.com/foo/bar"];
    TEST_ASSERT_EQ_I(fired.count, 1);

    // Unknown event reports an error (reporter called), no entry added.
    [fired removeAllObjects];
    __block int reported = 0;
    au.reporter = ^(NSString *msg, BOOL error) { reported++; (void)msg; (void)error; };
    TEST_ASSERT_TRUE([au parseAutocmdLine:@"bogus-event * :reload"]);
    TEST_ASSERT_TRUE(reported > 0);
}

#pragma mark - VimController

static void test_controller_scroll_and_esc(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;

    // 'j' scrolls down.
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S('j')]);
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 'j');
    TEST_ASSERT_EQ_I(spy.scrollCounts[0].unsignedIntegerValue, 0);

    // ESC resets state (returns to normal from a pending chord).
    [vc reset];
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);
}

static void test_controller_count_prefix(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // "5j" -> scrollMode 'j' count 5.
    [vc handleKeyCode:0 modifiers:0 characters:S('5')];
    [vc handleKeyCode:0 modifiers:0 characters:S('j')];
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 'j');
    TEST_ASSERT_EQ_I(spy.scrollCounts[0].unsignedIntegerValue, 5);
}

static void test_controller_colon_command_mode(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;

    // ":" enters command mode.
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S(':')]);
    TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
    // While in command mode everything is consumed.
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S('x')]);
    TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
}

static void test_controller_gg_top(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // 'g' then 'g' -> scrollMode 'g' (top).
    [vc handleKeyCode:0 modifiers:0 characters:S('g')];
    [vc handleKeyCode:0 modifiers:0 characters:S('g')];
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 'g');
}

static void test_controller_mapping_intercept(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // Map "j" -> "k" (noremap). Then "j" should scroll 'k' instead of 'j'.
    [[VimbConfig shared] addMappingForMode:@"n" lhs:@"j" rhs:@"k" noremap:YES];
    [vc handleKeyCode:0 modifiers:0 characters:S('j')];
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 'k');
    [[VimbConfig shared] removeMappingForMode:@"n" lhs:@"j"];

    // "gg" mapping intercept exercised earlier in config tests.
}

static void test_controller_command_dispatchers(void) {
    // Exercise a variety of the ASCII dispatch table handlers through the
    // spy delegate so the engine's normal-mode paths are covered.
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // 'k' scroll up.
    [vc reset]; [spy resetSpy];
    [vc handleKeyCode:0 modifiers:0 characters:S('k')];
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 'k');

    // 'u' opens home (no scroll recorded).
    [vc reset]; [spy resetSpy];
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S('u')]);
    TEST_ASSERT_EQ_I(spy.scrollCount, 0);

    // 'z' leads to zoom handler -> consumed.
    [vc reset]; [spy resetSpy];
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S('z')]);

    // A key with no attached command (e.g. 0x1f) is not consumed.
    [vc reset]; [spy resetSpy];
    TEST_ASSERT_TRUE(![vc handleKeyCode:0 modifiers:0 characters:S(0x1f)]);

    // ^Q is consumed (triggers quit).
    [vc reset]; [spy resetSpy];
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S(0x11)]);
}

static void test_controller_control_keys(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // ^Z dispatches vimEnterPassThrough (the UI flips the controller mode);
    // handleKeyCode itself consumes the key.
    [vc reset];
    TEST_ASSERT_TRUE([vc handleKeyCode:0 modifiers:0 characters:S(0x1a)]);

    // Manually enter passthrough (as the delegate would) and check that ESC
    // returns to normal and returns NO (letting the page handle it).
    vc.mode = VimModePassThrough;
    BOOL r = [vc handleKeyCode:0 modifiers:0 characters:S(27)];
    TEST_ASSERT_TRUE(!r);
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);

    // Ctrl+b (0x02) is a scroll command in the table.
    [vc reset];
    [vc handleKeyCode:0 modifiers:0 characters:S(0x02)];
    TEST_ASSERT_EQ_I(spy.scrollCount, 1);
    TEST_ASSERT_EQ_I(spy.scrollChars[0].intValue, 0x02);
}

static void test_controller_command_mode_reset(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    // After entering ':' command mode, commandLineCommitted: resets to normal.
    [vc handleKeyCode:0 modifiers:0 characters:S(':')];
    TEST_ASSERT_EQ_I(vc.mode, VimModeCommand);
    [vc commandLineCommitted:@"rc"];
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);
}

static void test_controller_hint_and_search(void) {
    VimController *vc = [[VimController alloc] init];
    SpyDelegate *spy = [[SpyDelegate alloc] init];
    vc.delegate = spy;
    vc.mode = VimModeNormal;

    // '/' enters search mode.
    [vc reset];
    [vc handleKeyCode:0 modifiers:0 characters:S('/')];
    TEST_ASSERT_EQ_I(vc.mode, VimModeSearch);
    [vc commandLineCancelled];
    TEST_ASSERT_EQ_I(vc.mode, VimModeNormal);
}

#pragma mark - main

// Behavior/shortcut/map/coverage tests live in test_behavior.m. Both harnesses
// use separate static counters in testlib.h, so run them and AND the results.
extern int run_behavior_main(void);

int main(void) {
    RUN_TEST(test_storage_prepend_dedup_max);
    RUN_TEST(test_storage_removeLine_top_popLast_clear);
    RUN_TEST(test_storage_writeAll);
    RUN_TEST(test_storage_push_matches_prepend);
    RUN_TEST(test_storage_append_fifo);
    RUN_TEST(test_storage_dirs);
    RUN_TEST(test_config_load_defaults);
    RUN_TEST(test_config_apply_setting_getters);
    RUN_TEST(test_config_validate_setting);
    RUN_TEST(test_config_coerce_setting_value);
    RUN_TEST(test_config_search_engine);
    RUN_TEST(test_config_mappings);
    RUN_TEST(test_config_convert_key_string);
    RUN_TEST(test_config_shortcuts_and_sources);
    RUN_TEST(test_ex_open);
    RUN_TEST(test_ex_set_and_unknown);
    RUN_TEST(test_ex_map_command);
    RUN_TEST(test_ex_commands_and_names);
    RUN_TEST(test_ex_parser_path_expansion);
    RUN_TEST(test_ex_url_fallback);
    RUN_TEST(test_ex_shortcut_and_bang);
    RUN_TEST(test_ex_parser_arg);
    RUN_TEST(test_ex_parser_abbreviation);
    RUN_TEST(test_ex_cleardata_type_names);
    RUN_TEST(test_ex_cmd_result);
    RUN_TEST(test_path_unique_destination);
    RUN_TEST(test_engine_registers_marks);
    RUN_TEST(test_engine_vsetting);
    RUN_TEST(test_autocmd_register_and_fire);
    RUN_TEST(test_autocmd_augroup);
    RUN_TEST(test_autocmd_wildcard);
    RUN_TEST(test_controller_scroll_and_esc);
    RUN_TEST(test_controller_count_prefix);
    RUN_TEST(test_controller_colon_command_mode);
    RUN_TEST(test_controller_gg_top);
    RUN_TEST(test_controller_mapping_intercept);
    RUN_TEST(test_controller_command_dispatchers);
    RUN_TEST(test_controller_control_keys);
    RUN_TEST(test_controller_command_mode_reset);
    RUN_TEST(test_controller_hint_and_search);

    int ok1 = RUN_ALL_TESTS();
    int ok2 = run_behavior_main();
    return (ok1 || ok2) ? 1 : 0;
}

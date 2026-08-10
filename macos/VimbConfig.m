#import "VimbConfig.h"
#import "VimbEngine.h"

static const NSString *DOWNLOAD_COMMAND = @"/usr/bin/xdg-open %s 2>/dev/null";
static const NSString *HINT_KEYS = @"abcdefghijklmnopqrstuvwxyz";
static const NSString *HOME_PAGE = @"about:blank";
static const NSString *COOKIE_ACCEPT = @"ask";

@implementation VimbConfig

+ (instancetype)shared {
    static VimbConfig *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[VimbConfig alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _settings = [NSMutableDictionary dictionary];
        _shortcuts = [NSMutableDictionary dictionary];
        _historyStore = [[VimbStorage alloc] initWithName:@"history"];
        _commandStore = [[VimbStorage alloc] initWithName:@"command"];
        _searchStore = [[VimbStorage alloc] initWithName:@"search"];
        _bookmarkStore = [[VimbStorage alloc] initWithName:@"bookmark"];
        _closedStore = [[VimbStorage alloc] initWithName:@"closed"];
        _queueStore = [[VimbStorage alloc] initWithName:@"queue"];
        _scrollstep = 40;
        _historyMax = 2000;
        _closedMax = 10;
        _incsearch = YES;
        _hintTimeout = 1000;
        _homePage = [HOME_PAGE copy];
        _hintKeys = [HINT_KEYS copy];
    }
    return self;
}

- (void)addSetting:(NSString *)name type:(VSettingType)type value:(id)value {
    NSString *compact = [name stringByReplacingOccurrencesOfString:@"-" withString:@""];
    [self.settings setObject:value forKey:name];
    // Cache the commonly-read scalars for fast dispatch.
    if ([compact isEqualToString:@"scrollstep"])                 { _scrollstep = [value integerValue]; }
    else if ([compact isEqualToString:@"historymaxitems"])       { _historyMax = [value integerValue]; }
    else if ([compact isEqualToString:@"closedmaxitems"])        { _closedMax = [value integerValue]; }
    else if ([compact isEqualToString:@"incsearch"])             { _incsearch = [value boolValue]; }
    else if ([compact isEqualToString:@"smoothscrolling"])       { _smoothScrolling = [value boolValue]; }
    else if ([compact isEqualToString:@"hintfollowlast"])        { _hintFollowLast = [value boolValue]; }
    else if ([compact isEqualToString:@"hintkeyssamelength"])    { _hintKeysSameLength = [value boolValue]; }
    else if ([compact isEqualToString:@"hintmatchelement"])      { _hintMatchElement = [value boolValue]; }
    else if ([compact isEqualToString:@"hintkeys"])              { _hintKeys = [value copy]; }
    else if ([compact isEqualToString:@"hinttimeout"])           { _hintTimeout = [value integerValue]; }
    else if ([compact isEqualToString:@"homepage"])              { _homePage = [value copy]; }
}

- (void)loadDefaults {
    VSettingType B = VSettingBool;
    VSettingType I = VSettingInt;
    VSettingType C = VSettingChar;

    [self addSetting:@"user-agent" type:C value:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 vimb/3.7.0"];
    [self addSetting:@"allow-file-access-from-file-urls" type:B value:@NO];
    [self addSetting:@"allow-universal-access-from-file-urls" type:B value:@NO];
    [self addSetting:@"caret" type:B value:@NO];
    [self addSetting:@"cursive-font" type:C value:@"serif"];
    [self addSetting:@"dark-mode" type:B value:@NO];
    [self addSetting:@"default-charset" type:C value:@"utf-8"];
    [self addSetting:@"default-font" type:C value:@"sans-serif"];
    [self addSetting:@"font-size" type:I value:@16];
    [self addSetting:@"geolocation" type:C value:@"ask"];
    [self addSetting:@"hardware-acceleration-policy" type:C value:@"ondemand"];
    [self addSetting:@"header" type:C value:@""];
    [self addSetting:@"hint-timeout" type:I value:@1000];
    [self addSetting:@"hint-keys" type:C value:[HINT_KEYS copy]];
    [self addSetting:@"hint-follow-last" type:B value:@YES];
    [self addSetting:@"hint-keys-same-length" type:B value:@NO];
    [self addSetting:@"hint-match-element" type:B value:@YES];
    [self addSetting:@"histignore" type:C value:@".*youtube\\..*"];
    [self addSetting:@"html5-database" type:B value:@YES];
    [self addSetting:@"html5-local-storage" type:B value:@YES];
    [self addSetting:@"images" type:B value:@YES];
    [self addSetting:@"intelligent-tracking-prevention" type:B value:@NO];
    [self addSetting:@"javascript-can-access-clipboard" type:B value:@NO];
    [self addSetting:@"javascript-can-open-windows-automatically" type:B value:@NO];
    [self addSetting:@"javascript-enable-markup" type:B value:@YES];
    [self addSetting:@"media" type:B value:@YES];
    [self addSetting:@"media-playback-allows-inline" type:B value:@YES];
    [self addSetting:@"media-playback-requires-user-gesture" type:B value:@NO];
    [self addSetting:@"media-stream" type:B value:@NO];
    [self addSetting:@"mediasource" type:B value:@NO];
    [self addSetting:@"minimum-font-size" type:I value:@5];
    [self addSetting:@"monospace-font" type:C value:@"monospace"];
    [self addSetting:@"notification" type:C value:@"ask"];
    [self addSetting:@"prevent-newwindow" type:B value:@NO];
    [self addSetting:@"print-backgrounds" type:B value:@YES];
    [self addSetting:@"sans-serif-font" type:C value:@"sans-serif"];
    [self addSetting:@"scripts" type:B value:@YES];
    [self addSetting:@"serif-font" type:C value:@"serif"];
    [self addSetting:@"site-specific-quirks" type:B value:@NO];
    [self addSetting:@"smooth-scrolling" type:B value:@NO];
    [self addSetting:@"spatial-navigation" type:B value:@NO];
    [self addSetting:@"tabs-to-links" type:B value:@YES];
    [self addSetting:@"webaudio" type:B value:@NO];
    [self addSetting:@"webgl" type:B value:@NO];
    [self addSetting:@"webinspector" type:B value:@NO];
    [self addSetting:@"stylesheet" type:B value:@YES];
    [self addSetting:@"user-scripts" type:B value:@YES];
    [self addSetting:@"cookie-accept" type:C value:[COOKIE_ACCEPT copy]];
    [self addSetting:@"scroll-step" type:I value:@40];
    [self addSetting:@"scroll-multiplier" type:I value:@1];
    [self addSetting:@"home-page" type:C value:[HOME_PAGE copy]];
    [self addSetting:@"status-bar-show-settings" type:B value:@NO];
    [self addSetting:@"history-max-items" type:I value:@2000];
    [self addSetting:@"editor-command" type:C value:@"/usr/bin/open -t '%s'"];
    [self addSetting:@"strict-ssl" type:B value:@YES];
    [self addSetting:@"status-bar" type:B value:@YES];
    [self addSetting:@"timeoutlen" type:I value:@1000];
    [self addSetting:@"input-autohide" type:B value:@YES];
    [self addSetting:@"fullscreen" type:B value:@NO];
    [self addSetting:@"show-titlebar" type:B value:@YES];
    [self addSetting:@"default-zoom" type:I value:@100];
    [self addSetting:@"download-path" type:C value:@"/Users/Shared/Downloads"];
    [self addSetting:@"download-command" type:C value:[DOWNLOAD_COMMAND copy]];
    [self addSetting:@"download-use-external" type:B value:@NO];
    [self addSetting:@"incsearch" type:B value:@YES];
    [self addSetting:@"closed-max-items" type:I value:@10];
    [self addSetting:@"x-hint-command" type:C value:@":o <C-R>;"];
    [self addSetting:@"spell-checking" type:B value:@NO];
    [self addSetting:@"spell-checking-languages" type:C value:@"en_US"];
    [self addSetting:@"completion-css" type:C value:@""];
    [self addSetting:@"completion-hover-css" type:C value:@""];
    [self addSetting:@"completion-selected-css" type:C value:@""];
    [self addSetting:@"input-css" type:C value:@""];
    [self addSetting:@"input-error-css" type:C value:@""];
    [self addSetting:@"status-css" type:C value:@""];
    [self addSetting:@"status-ssl-css" type:C value:@""];
    [self addSetting:@"status-ssl-invalid-css" type:C value:@""];

    // Shortcuts (mirror setting_init).
    self.shortcuts[@"dl"] = @"https://duckduckgo.com/html/?q=$0";
    self.shortcuts[@"dd"] = @"https://duckduckgo.com/?q=$0";
    self.defaultShortcut = @"dl";

    // download path
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
    if (paths.firstObject) {
        [self addSetting:@"download-path" type:C value:paths.firstObject];
    }
}

- (id)get:(NSString *)name {
    return self.settings[name];
}

- (BOOL)getBool:(NSString *)name defaultValue:(BOOL)dv {
    id v = self.settings[name];
    return v ? [v boolValue] : dv;
}

- (NSInteger)getInt:(NSString *)name defaultValue:(NSInteger)dv {
    id v = self.settings[name];
    return v ? [v integerValue] : dv;
}

- (NSString *)getString:(NSString *)name defaultValue:(NSString *)dv {
    id v = self.settings[name];
    return (v && ![v isEqual:@(0)] && [v isKindOfClass:[NSString class]]) ? v : dv;
}

- (void)applySetting:(NSString *)name value:(id)value {
    self.settings[name] = value;
    [self addSetting:name type:[value isKindOfClass:[NSNumber class]] ?
            (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ? VSettingBool : VSettingInt)
            : VSettingChar
         value:value];
}

- (nullable NSString *)resolveShortcut:(NSString *)input {
    NSString *s = self.shortcuts[input];
    if (!s) { return nil; }
    return s;
}

- (NSString *)historyCommand {
    return [[VimbStorage appSupportDir] stringByAppendingPathComponent:@"config"];
}

- (void)sourceConfigFile {
    // Parse rc file: each non-comment line is an ex command; run them.
    NSString *path = self.historyCommand;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) { return; }
    for (NSString *raw in [content componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"\""] || [line hasPrefix:@"#"]) { continue; }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"VimbRunCommand"
            object:nil userInfo:@{@"command": line}];
    }
}

@end

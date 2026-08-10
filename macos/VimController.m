#import "VimController.h"
#import <ctype.h>
#import <string.h>

// Faithful port of vimb's normal-mode engine (src/normal.c normal_keypress).
// The phase parser, the ASCII command dispatch table and the per-command
// behavior mirror the original GTK4/WebKitGTK implementation, adapted to the
// native macOS delegate.

typedef NS_ENUM(NSInteger, HBPhase) {
    HBPhaseStart = 0,
    HBPhaseKey2,
    HBPhaseKey3,
    HBPhaseReg,
    HBPhaseComplete
};

typedef NS_ENUM(NSInteger, HBResult) {
    HBResultComplete = 0,
    HBResultMore,
    HBResultError
};

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

static BOOL is_digit(int key)   { return key >= '0' && key <= '9'; }
static BOOL is_alpha(int key)   { return isalpha(key) != 0; }
static BOOL is_reg_char(int key){ return strchr("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:%/;", key) != NULL; }

// Command handler type. Returns HBResult.
typedef HBResult (^HBCommand)(unichar unicode, int key, unichar key2, unichar key3, NSInteger count, int reg);

#pragma clang diagnostic pop

@interface VimController ()
@property(nonatomic, assign) HBPhase phase;
@property(nonatomic, assign) int lastKey;       // key passed into parser (event keysym)
@property(nonatomic, assign) unichar ukey;      // unicode char
@property(nonatomic, assign) unichar key2;
@property(nonatomic, assign) unichar key3;
@property(nonatomic, assign) NSInteger count;
@property(nonatomic, assign) int reg;
@property(nonatomic, copy, nullable) NSString *promptForMode;
@end

@implementation VimController

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = VimModeNormal;
        [self resetParser];
    }
    return self;
}

- (void)resetParser {
    _phase = HBPhaseStart;
    _lastKey = 0; _ukey = 0; _key2 = 0; _key3 = 0; _count = 0; _reg = 0;
}

- (void)reset {
    self.mode = VimModeNormal;
    [self resetParser];
}

- (void)commandLineCancelled {
    [self reset];
    id<VimDelegate> d = self.delegate;
    if (d && [d respondsToSelector:@selector(vimFocusWebView)]) { [d vimFocusWebView]; }
}

- (void)commandLineCommitted:(NSString *)line {
    VimMode m = self.mode;
    id<VimDelegate> d = self.delegate;
    if (m == VimModeSearch && line.length > 0) {
        if (d) [d vimSearch:line forward:[self.promptForMode isEqualToString:@"forward"]];
    }
    // Command mode is handled directly on the UI side via the command field.
    [self reset];
    if (d && [d respondsToSelector:@selector(vimFocusWebView)]) { [d vimFocusWebView]; }
}

#pragma mark - Key decoding

- (BOOL)handleKeyDown:(NSEvent *)event inWebView:(BOOL)inWebView {
    (void)inWebView;
    id<VimDelegate> d = self.delegate;

    NSEventModifierFlags mods = event.modifierFlags;
    BOOL ctrl = (mods & NSEventModifierFlagControl) != 0;
    BOOL cmd  = (mods & NSEventModifierFlagCommand) != 0;

    // Prompt modes consume everything except a few explicit passthroughs.
    if (self.mode == VimModeCommand || self.mode == VimModeSearch) {
        return YES;
    }

    if (self.mode == VimModeHint) {
        NSString *cs = event.charactersIgnoringModifiers;
        if (cs.length == 0) return YES;
        unichar c = [cs characterAtIndex:0];
        if (c == 27) {                       // ESC cancels
            [d vimToggleHints];
            [self reset];
        } else if (c == '\t') {
            [d vimToggleHints];
            [self reset];
        } else if (isprint(c) || c == ' ') {
            [d vimHintKey:[[NSString alloc] initWithCharacters:&c length:1]];
        }
        return YES;
    }

    NSString *chars = event.charactersIgnoringModifiers;
    if (chars.length == 0) {
        return NO;
    }
    unichar c = [chars characterAtIndex:0];
    int keysym = (int)c;

    // Control keys come through as unicode control chars (e.g. 0x04 for ^D);
    // convert accented/mac control codes to the raw control char when possible.
    // We pass both the raw unicode and a control-char derivation to the parser.

    if (cmd && ![chars isEqualToString:@"gh"]) {
        // Leave Cmd shortcuts (copy/paste/find) to the app menu / WebKit.
        return NO;
    }

    unichar controlChar = 0;
    if (ctrl && isalpha(c)) {
        controlChar = (unichar)(c >= 'a' && c <= 'z' ? (c - 'a' + 1) : (c - 'A' + 1));
    } else if ((int)c >= 1 && (int)c <= 26) {
        controlChar = c;   // already a control char from the pasteboard/keyboard
    }

    // Feed control chars through the parser keyed by control value.
    if (controlChar != 0) {
        HBResult r = [self runParserWithKey:keysym unicode:controlChar];
        return [self finishParse:r];
    }

    HBResult res = [self runParserWithKey:keysym unicode:c];
    return [self finishParse:res];
}

// Returns YES when the key event was fully consumed by vim (mirrors vimb's
// RESULT_COMPLETE / RESULT_MORE semantics mapped onto how much should pass to
// the page). RESULT_ERROR means no command was attached: pass through.
- (BOOL)finishParse:(HBResult)res {
    switch (res) {
        case HBResultComplete:
            return YES;
        case HBResultMore:
            // Still accumulating a chord (e.g. waiting for the second key).
            return self.phase != HBPhaseStart;
        case HBResultError:
        default:
            return NO;
    }
}

- (void)resetParserAfterDispatch {
    // Count/keys are reset after a completed command; the running info object
    // in vimb is reset in normal_keypress. Reapply: keep plain state fresh.
    self.count = 0;
    self.ukey = 0; self.key2 = 0; self.key3 = 0; self.reg = 0;
    self.phase = HBPhaseStart;
}

- (HBResult)runParserWithKey:(int)key unicode:(unichar)c {
    id<VimDelegate> d = self.delegate;
    HBResult res = HBResultMore;

    switch (self.phase) {
        case HBPhaseStart:
            if (self.count == 0 && c == '0') {
                self.ukey = c;
                self.lastKey = key;
                self.phase = HBPhaseComplete;
            } else if (is_digit((int)c)) {
                self.count = self.count * 10 + ((int)c - '0');
                return HBResultMore;
            } else if (strchr(";zg[]'m", c)) {
                /* commands that need an additional char */
                self.phase = HBPhaseKey2;
                self.ukey  = c;
                self.lastKey = key;
            } else if (c == '"') {
                self.phase = HBPhaseReg;
            } else {
                self.ukey = c;
                self.lastKey = key;
                self.phase = HBPhaseComplete;
            }
            break;

        case HBPhaseKey2:
            self.key2 = c;
            /* g; hinting requires a third key */
            if (self.ukey == 'g' && c == ';') {
                self.phase = HBPhaseKey3;
            } else {
                self.phase = HBPhaseComplete;
            }
            break;

        case HBPhaseKey3:
            self.key3 = c;
            self.phase = HBPhaseComplete;
            break;

        case HBPhaseReg:
            if (is_reg_char((int)c)) {
                self.reg = c;
                self.phase = HBPhaseStart;
            } else {
                self.phase = HBPhaseComplete;
            }
            break;

        case HBPhaseComplete:
            break;
    }

    if (self.phase == HBPhaseComplete) {
        NSArray *mapped = [self commandForKey:(unichar)self.ukey];
        if (mapped == nil) {
            // No command attached: let the platform handle the key.
            return HBResultError;
        }
        HBResult r = [self invokeHandler:mapped c:self.ukey k:self.lastKey k2:self.key2 k3:self.key3 cnt:self.count reg:self.reg delegate:d];
        if (r == HBResultComplete || r == HBResultError) {
            [self resetParserAfterDispatch];
        }
        return r==HBResultError ? HBResultComplete : r;
    }

    return res;
}

- (NSArray *)commandForKey:(unichar)key {
    // Mirrors vimb's commands[] table in src/normal.c.
    switch (key) {
        case 0x01: return @[@"inc"];         // ^A
        case 0x02: return @[@"scroll"];      // ^B
        case 0x03: return @[@"reload"];      // ^C
        case 0x04: return @[@"scroll"];      // ^D
        case 0x06: return @[@"scroll"];      // ^F
        case 0x09: return @[@"forward"];     // ^I  (next from history handled as forward)
        case 0x0d: return @[@"fire"];        // ^M (Enter)
        case 0x0f: return @[@"back"];        // ^O
        case 0x11: return @[@"quit"];        // ^Q
        case 0x15: return @[@"scroll"];      // ^U
        case 0x1a: return @[@"pass"];        // ^Z
        case 0x1b: return @[@"esc"];         // ESC
        case 0x18: return @[@"dec"];         // ^X
        case ' ' : return @[@"scroll"];      // space (scroll down a page)
        case '#': case '*':
                        return @[@"searchsel"];
        case '\'': return @[@"mark"];
        case '/': case '?': return @[@"cmdline"];   // search prompts
        case ':': return @[@"cmdline"];
        case ';': return @[@"hint"];
        case '$': case '0': return @[@"scroll"];
        case 'F': case 'f': return @[@"cmdline"];   // f/F lead-in (find/hint follow)
        case 'G': case 'H': case 'M': case 'L':
                        return @[@"scroll"];
        case 'N': case 'n': return @[@"search"];
        case 'O': case 'o': case 'T': case 't':
                        return @[@"inputopen"];
        case 'P': case 'p': return @[@"openclipboard"];
        case 'R': case 'r': return @[@"reload"];
        case 'U': case 'u': return @[@"home"];
        case 'Y': case 'y': return @[@"yank"];
        case '[': case ']': return @[@"prevnext"];
        case 'g': return @[@"g_cmd"];
        case 'h': case 'j': case 'k': case 'l':
                        return @[@"scroll"];
        case 'i': return @[@"focuslast"];
        case 'm': return @[@"mark"];
        case 'z': return @[@"zoom"];
        default: return nil;
    }
}

#pragma mark - Command handlers

- (HBResult)invokeHandler:(NSArray *)sel c:(unichar)c k:(int)k k2:(unichar)k2 k3:(unichar)k3
                    cnt:(NSInteger)cnt reg:(int)reg delegate:(id<VimDelegate>)d {
    NSString *name = sel[0];

    if ([name isEqualToString:@"scroll"]) {
        [d vimScrollMode:c count:(NSUInteger)cnt];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"reload"]) {
        [d vimReload];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"back"]) { [d vimGoBack]; return HBResultComplete; }
    if ([name isEqualToString:@"forward"]) { [d vimGoForward]; return HBResultComplete; }
    if ([name isEqualToString:@"stop"]) { [d vimStop]; return HBResultComplete; }
    if ([name isEqualToString:@"fire"]) {
        [d vimFire];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"quit"]) {
        [d vimQuit];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"pass"]) {
        [d vimEnterPassThrough];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"esc"]) {
        [self reset];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"inc"]) { [d vimIncrement:YES]; return HBResultComplete; }
    if ([name isEqualToString:@"dec"]) { [d vimIncrement:NO]; return HBResultComplete; }
    if ([name isEqualToString:@"searchsel"]) {
        [d vimSearchSelectionForward:(c == '*')];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"search"]) {
        NSInteger dir = (c == 'n') ? (cnt > 0 ? cnt : 1) : -(cnt > 0 ? cnt : 1);
        [d vimSearchDirection:dir];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"mark"]) {
        [self showUnsupported:@"mark" d:d];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"cmdline"]) {
        if (c == 'f' || c == 'F') {
            // f/F: enter hint mode and follow a link. Hints engine owns the
            // overlay; the webview stays focused so typed keys filter hints.
            [d vimOpenPrompt:@"" mode:VimModeHint];
            [d vimToggleHints];
        } else if (c == '/' || c == '?') {
            [d vimOpenPrompt:[NSString stringWithFormat:@"%c", c] mode:VimModeSearch];
            self.promptForMode = (c == '/') ? @"forward" : @"backward";
        } else {
            [d vimOpenPrompt:@":" mode:VimModeCommand];
        }
        return HBResultComplete;
    }
    if ([name isEqualToString:@"hint"]) {
        // ';' + follow key: enter hint mode.
        [d vimOpenPrompt:@"" mode:VimModeHint];
        [d vimToggleHints];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"inputopen"]) {
        // o/O/t/T : open prompt prefilled with the current URI.
        BOOL tab = (c == 'O' || c == 'T');
        NSString *prefix = tab ? @"tabopen " : @"open ";
        NSString *cur = @"";
        [d vimOpenPrompt:prefix mode:VimModeCommand];
        (void)cur;
        return HBResultComplete;
    }
    if ([name isEqualToString:@"openclipboard"]) {
        [d vimOpenClipboard:[NSString stringWithFormat:@"%c", (self.reg ? self.reg : '0')]];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"home"]) {
        [d vimOpenHome];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"yank"]) {
        [d vimYankURI];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"focuslast"]) {
        [d vimFocusLastActive];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"zoom"]) {
        [d vimZoom:(cnt >= 0 ? YES : NO)];
        return HBResultComplete;
    }
    if ([name isEqualToString:@"prevnext"]) {
        return HBResultError; // not implemented in the original shell either
    }
    if ([name isEqualToString:@"g_cmd"]) {
        return [self invokeGCmd:c k2:k2 k3:k3 cnt:cnt delegate:d];
    }

    return HBResultError;
}

- (void)showUnsupported:(NSString *)name d:(id<VimDelegate>)d {
    [d vimShowMessage:[NSString stringWithFormat:@"%@ not yet supported on native backend", name] error:YES];
}

- (HBResult)invokeGCmd:(unichar)key k2:(unichar)k2 k3:(unichar)k3 cnt:(NSInteger)cnt delegate:(id<VimDelegate>)d {
    switch (k2) {
        case 'g':
            [d vimScrollMode:'g' count:(NSUInteger)cnt];
            return HBResultComplete;
        case 'h': case 'H':
            if (k2 == 'H') { /* open homepage / new tab? gH goes home */ [d vimOpenHome]; }
            return HBResultComplete;
        case 'i':
            [d vimFocusInput];
            return HBResultComplete;
        case 't':
            [d vimNextTab];
            return HBResultComplete;
        case 'T':
            [d vimPrevTab];
            return HBResultComplete;
        case '0':
            [d vimGotoTab:0];
            return HBResultComplete;
        case '$':
            [d vimGotoTab:NSNotFound];
            return HBResultComplete;
        case 'f':
        case 'F':
            [self showUnsupported:@"view source" d:d];
            return HBResultComplete;
        case ';': {
            [d vimToggleHints];
            return HBResultComplete;
        }
        default:
            return HBResultError;
    }
}

@end

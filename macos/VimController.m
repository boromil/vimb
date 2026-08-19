#import "VimController.h"
#import "VimbConfig.h"
#import "VimbHintEngine.h"
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
@property(nonatomic, strong) NSMutableString *mapBuffer;   // pending unmapped keys (normal mode)
@property(nonatomic, assign) int mapDepth;                  // recursion guard for remap
@end

@implementation VimController

- (BOOL)shouldPassKeysToPage:(BOOL)pageEditableActive {
    if (!pageEditableActive) { return NO; }
    // Only normal-mode pages let the field take the keys; while typing in the
    // command line/search or hinting, vim keeps the keys.
    if (self.mode != VimModeNormal) { return NO; }
    return YES;
}

// Input-mode key handling (port of input.c input_keypress): Ctrl-O enters a
// one-shot normal command; while that is active, subsequent keys run through
// the normal-mode parser until the command completes.
- (BOOL)handlePageEditableKeyCode:(int)keyCode
                        modifiers:(unsigned long)mods
                       characters:(NSString *)charsIgnoring {
    if (self.oneShotNormal) {
        // Route the next key(s) through normal-mode; clear one-shot when the
        // command is complete (not waiting for more keys).
        [self handleKeyCode:keyCode modifiers:mods characters:charsIgnoring];
        if (self.phase == HBPhaseStart) {
            self.oneShotNormal = NO;
        }
        return YES;
    }
    // Ctrl-O (Ctrl + 'O') enters one-shot normal mode.
    if ((mods & 1UL << 18) != 0 && keyCode == (int)'O') {
        self.oneShotNormal = YES;
        return YES;
    }
    // Ctrl-T opens the external editor for the focused field (input.c).
    if ((mods & 1UL << 18) != 0 && keyCode == (int)'T') {
        id<VimDelegate> d = self.delegate;
        if (d && [d respondsToSelector:@selector(vimOpenEditor)]) { [d vimOpenEditor]; }
        return YES;
    }
    // ESC is handled by the UI (blur); everything else goes to the page.
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _oneShotNormal = NO;
        _mode = VimModeNormal;
        _mapBuffer = [[NSMutableString alloc] init];
        [self resetParser];
    }
    return self;
}

- (void)resetParser {
    _phase = HBPhaseStart;
    _lastKey = 0; _ukey = 0; _key2 = 0; _key3 = 0; _count = 0; _reg = 0;
    if (_mapBuffer) { [_mapBuffer setString:@""]; }
    _mapDepth = 0;
}

- (void)reset {
    self.mode = VimModeNormal;
    self.oneShotNormal = NO;
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
    NSString *chars = event.charactersIgnoringModifiers;
    // charactersIgnoringModifiers drops Shift: pressing Shift-F yields "f", so
    // shifted normal-mode commands (gF, gH, gT vs gt) could never be reached.
    // Re-apply Shift for single ASCII letters so the parser sees the intended
    // uppercase command character.
    if ((event.modifierFlags & NSEventModifierFlagShift) != 0
        && chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'a' && c <= 'z') {
            chars = [NSString stringWithFormat:@"%C", (unichar)(c - 'a' + 'A')];
        }
    }
    return [self handleKeyCode:(int)event.keyCode
                     modifiers:(unsigned long)event.modifierFlags
                    characters:chars];
}

- (BOOL)handleKeyCode:(int)keyCode
            modifiers:(unsigned long)mods
        characters:(NSString *)chars {
    (void)keyCode;
    id<VimDelegate> d = self.delegate;

    BOOL ctrl = (mods & (1UL << 18)) != 0;   // NSEventModifierFlagControl = 1 << 18
    BOOL cmd  = (mods & (1UL << 20)) != 0;   // NSEventModifierFlagCommand = 1 << 20

    // Prompt modes consume everything except a few explicit passthroughs.
    if (self.mode == VimModeCommand || self.mode == VimModeSearch) {
        return YES;
    }

    if (self.mode == VimModePassThrough) {
        // All keys go to the page except ESC, which returns to normal mode.
        if (chars.length && [chars characterAtIndex:0] == 27) {
            self.mode = VimModeNormal;
            [d vimFocusWebView];
        }
        return NO; // let the page handle the key
    }

    if (self.mode == VimModeHint) {
        if (chars.length == 0) return YES;
        unichar c = [chars characterAtIndex:0];
        if (c == 27) {                       // ESC cancels
            [d vimToggleHints];
            [self reset];
        } else if (c == '\t') {              // Tab / Shift-Tab move focus next/prev
            BOOL shift = (mods & (1UL << 17)) != 0;   // NSEventModifierFlagShift = 1 << 17
            [d vimHintFocus:shift];          // back=shift
        } else if (c == 0x7f || c == 0x08) { // Backspace removes last filter key
            [d vimHintBackspace];
        } else if (c == '\r' || c == '\n') { // Enter fires the focused hint
            [d vimHintFire];
        } else if (c == 0x04 || c == 0x06 || c == 0x02 || c == 0x15 ||
                   (ctrl && isalpha(c) && strchr("dfbu", c | 0x20) != NULL)) {
            // Ctrl-D/F/B/U still scroll (passthrough to vim scroll). Handle
            // both the raw control char and the ctrl+letter form.
            unichar cc = c;
            if (isalpha(c)) { cc = (unichar)((c >= 'a' && c <= 'z') ? (c - 'a' + 1) : (c - 'A' + 1)); }
            [d vimScrollMode:cc count:(NSUInteger)1];
        } else if (isprint(c) || c == ' ') {
            [d vimHintKey:[[NSString alloc] initWithCharacters:&c length:1]];
        }
        return YES;
    }

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
        return [self processMappedKey:controlChar keysym:keysym];
    }

    return [self processMappedKey:c keysym:keysym];
}

// Normal-mode mapping layer (port of map_handle_keys' lookup/resolve). The
// typed key is appended to a pending buffer; if it matches (or is a strict
// prefix of) a user mapping from VimbConfig, that mapping wins over the
// built-in table. Otherwise the front char(s) fall through to the parser.
// Returns YES when the key was consumed by vim.
- (BOOL)processMappedKey:(unichar)c keysym:(int)keysym {
    // Only normal mode applies runtime key mappings; other modes are handled
    // by the command line / page directly.
    if (self.mode != VimModeNormal) {
        HBResult r = [self runParserWithKey:keysym unicode:c];
        return [self finishParse:r];
    }

    [self.mapBuffer appendFormat:@"%C", c];
    return [self resolveMapBuffer];
}

- (BOOL)resolveMapBuffer {
    if (self.mapDepth > 64) {
        // Infinite remap guard.
        [self.mapBuffer setString:@""];
        return NO;
    }
    while (YES) {
        if (self.mapBuffer.length == 0) { return YES; }

        NSDictionary *res = [[VimbConfig shared] resolveMappingForMode:@"n" buffer:self.mapBuffer];
        NSString *status = res[@"status"];

        if ([status isEqualToString:@"ambiguous"]) {
            // The buffer is a strict prefix of a longer lhs: wait for more keys.
            return YES;
        }
        if ([status isEqualToString:@"match"]) {
            NSString *rhs = res[@"rhs"];
            BOOL noremap = [res[@"noremap"] boolValue];
            [self.mapBuffer setString:@""];

            if (rhs.length > 0 && [rhs characterAtIndex:0] == ':') {
                // rhs is an ex command: route it through the same channel the
                // config file / command line use so it actually takes effect.
                NSString *cmd = [rhs substringFromIndex:1];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"VimbRunCommand"
                    object:nil userInfo:@{@"command": cmd}];
                [self resetParserAfterDispatch];
                return YES;
            }

            if (noremap) {
                [self feedParserString:rhs];
                return YES;
            } else {
                // remap: re-resolve the rhs against the mappings (recursion).
                self.mapDepth++;
                [self.mapBuffer appendString:rhs];
                BOOL r = [self resolveMapBuffer];
                self.mapDepth--;
                return r;
            }
        }

        // "none": no mapping prefix matches; commit the front char to the
        // parser and re-evaluate the remainder (mirrors map_handle_keys
        // resolving one char at a time).
        unichar front = [self.mapBuffer characterAtIndex:0];
        [self.mapBuffer deleteCharactersInRange:NSMakeRange(0, 1)];
        HBResult r = [self runParserWithKey:(int)front unicode:front];
        if (r == HBResultError) {
            // Unmapped key with no attached command: let the platform handle it.
            [self.mapBuffer setString:@""];
            return NO;
        }
    }
}

// Feeds a mapped rhs (in parser form) to the normal parser, one char at a
// time. Returns NO if any char had no command attached.
- (BOOL)feedParserString:(NSString *)keys {
    BOOL consumed = YES;
    for (NSUInteger i = 0; i < keys.length; i++) {
        unichar c = [keys characterAtIndex:i];
        HBResult r = [self runParserWithKey:(int)c unicode:c];
        if (r == HBResultError) { consumed = NO; }
    }
    return consumed;
}

// Returns YES when the key event was fully consumed by vim (mirrors vimb's
// RESULT_COMPLETE / RESULT_MORE semantics mapped onto how much should pass to
// the page). RESULT_ERROR means no command was attached: pass through.
- (BOOL)finishParse:(HBResult)res {
    switch (res) {
        case HBResultComplete:
            return YES;
        case HBResultMore:
            // Still accumulating a chord (e.g. waiting for the second key) or
            // building a count — all of these are consumed.
            return YES;
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
        VimNormalCmd cmd = [self commandForKey:(unichar)self.ukey];
        if (cmd == VimCmdNone) {
            // No command attached: let the platform handle the key. Reset the
            // pending parser state so a subsequent key isn't misparsed.
            [self resetParserAfterDispatch];
            return HBResultError;
        }
        HBResult r = [self invokeHandler:cmd c:self.ukey k:self.lastKey k2:self.key2 k3:self.key3 cnt:self.count reg:self.reg delegate:d];
        if (r == HBResultComplete || r == HBResultError) {
            [self resetParserAfterDispatch];
        }
        return r;
    }

    return res;
}

// Typed dispatch (replaces the old string-array indirection): mirrors
// vimb's commands[] table in src/normal.c, but the compiler now checks
// every case in invokeHandler: below (-Wswitch enumerates VimNormalCmd).
- (VimNormalCmd)commandForKey:(unichar)key {
    switch (key) {
        case 0x01: return VimCmdInc;         // ^A
        case 0x02: return VimCmdScroll;      // ^B
        case 0x03: return VimCmdStop;        // ^C stop_loading (GTK normal_navigate)
        case 0x04: return VimCmdScroll;      // ^D
        case 0x06: return VimCmdScroll;      // ^F
        case 0x09: return VimCmdForward;     // ^I  (next from history handled as forward)
        case 0x0d: return VimCmdFire;        // ^M (Enter)
        case 0x0f: return VimCmdBack;        // ^O
        case 0x10: return VimCmdQueuePop;    // ^P (queue pop/load next)
        case 0x11: return VimCmdQuit;        // ^Q
        case 0x15: return VimCmdScroll;      // ^U
        case 0x1a: return VimCmdPass;        // ^Z
        case 0x1b: return VimCmdEsc;         // ESC
        case 0x18: return VimCmdDec;         // ^X
        case '#': case '*':
                        return VimCmdSearchSel;
        case '\'': return VimCmdMark;
        case '/': case '?': return VimCmdCmdline;   // search prompts
        case ':': return VimCmdCmdline;
        case ';': return VimCmdHint;
        case '$': case '0': return VimCmdScroll;
        case 'F': case 'f': return VimCmdCmdline;   // f/F lead-in (find/hint follow)
        case 'G':
                        return VimCmdScroll;   // G scroll; H/M/L pass through (GTK NULL)
        case 'N': case 'n': return VimCmdSearch;
        case 'O': case 'o': case 'T': case 't':
                        return VimCmdInputOpen;
        case 'P': case 'p': return VimCmdOpenClipboard;
        case 'R': return VimCmdReloadBypass;  // R reload_bypass_cache (GTK normal_navigate)
        case 'r': return VimCmdReload;        // r reload
        case 'U': case 'u': return VimCmdHome;
        case 'Y': case 'y': return VimCmdYank;
        case '[': case ']': return VimCmdPrevNext;
        case 'g': return VimCmdG;
        case 'h': case 'j': case 'k': case 'l':
                        return VimCmdScroll;
        case 'i': return VimCmdFocusLast;
        case 'm': return VimCmdMark;
        case 'z': return VimCmdZoom;
        default: return VimCmdNone;
    }
}

#pragma mark - Command handlers

- (HBResult)invokeHandler:(VimNormalCmd)cmd c:(unichar)c k:(int)k k2:(unichar)k2 k3:(unichar)k3
                    cnt:(NSInteger)cnt reg:(int)reg delegate:(id<VimDelegate>)d {
    switch (cmd) {
        case VimCmdScroll:
            [d vimScrollMode:c count:(NSUInteger)cnt];
            return HBResultComplete;
        case VimCmdReload:
            [d vimReload];
            return HBResultComplete;
        case VimCmdReloadBypass:
            [d vimReloadBypassCache];
            return HBResultComplete;
        case VimCmdBack:
            [d vimGoBack];
            return HBResultComplete;
        case VimCmdForward:
            [d vimGoForward];
            return HBResultComplete;
        case VimCmdStop:
            [d vimStop];
            return HBResultComplete;
        case VimCmdFire:
            [d vimFire];
            return HBResultComplete;
        case VimCmdQuit:
            [d vimQuit];
            return HBResultComplete;
        case VimCmdPass:
            [d vimEnterPassThrough];
            return HBResultComplete;
        case VimCmdEsc:
            [self reset];
            return HBResultComplete;
        case VimCmdInc:
            [d vimIncrement:YES count:cnt];
            return HBResultComplete;
        case VimCmdDec:
            [d vimIncrement:NO count:cnt];
            return HBResultComplete;
        case VimCmdSearchSel:
            [d vimSearchSelectionForward:(c == '*')];
            return HBResultComplete;
        case VimCmdSearch: {
            NSInteger dir = (c == 'n') ? (cnt > 0 ? cnt : 1) : -(cnt > 0 ? cnt : 1);
            [d vimSearchDirection:dir];
            return HBResultComplete;
        }
        case VimCmdMark:
            // m<char> sets a mark, '<char> jumps to it (vimb normal_mark).
            if (k2) {
                if (c == 'm') {
                    [d vimSetMark:k2];
                } else {
                    [d vimJumpMark:k2];
                }
            }
            return HBResultComplete;
        case VimCmdCmdline:
            if (c == 'f' || c == 'F') {
                // f: follow (current tab), F: follow in a new tab.
                self.mode = VimModeHint;
                [d vimOpenPrompt:@"" mode:VimModeHint];
                [d vimEnterHints:(c == 'F') ? @"t" : @"o" gmode:NO];
            } else if (c == '/' || c == '?') {
                self.mode = VimModeSearch;
                self.promptForMode = (c == '/') ? @"forward" : @"backward";
                [d vimOpenPrompt:[NSString stringWithFormat:@"%c", c] mode:VimModeSearch];
            } else {
                self.mode = VimModeCommand;
                [d vimOpenPrompt:@":" mode:VimModeCommand];
            }
            return HBResultComplete;
        case VimCmdHint: {
            // ';' + mode char (key2) chooses the hint action. Mirrors
            // hints_parse_prompt: an invalid mode simply clears any hint state.
            unichar hm = k2 ? k2 : 'o';
            if (![VimbHintEngine validMode:hm gmode:NO]) {
                [d vimToggleHints];
                [self reset];
                return HBResultComplete;
            }
            self.mode = VimModeHint;
            [d vimOpenPrompt:@"" mode:VimModeHint];
            [d vimEnterHints:[NSString stringWithFormat:@"%c", hm] gmode:NO];
            return HBResultComplete;
        }
        case VimCmdInputOpen: {
            // o/O/t/T : open prompt. Uppercase O/T pre-fills the current URI
            // (GTK normal_input_open src/normal.c:566-580).
            BOOL tab = (c == 't' || c == 'T');    // t/T -> tabopen, o/O -> open
            BOOL withURI = (c == 'O' || c == 'T');
            NSString *prefix = tab ? @"tabopen " : @"open ";
            if (withURI && [d respondsToSelector:@selector(vimCurrentURI)]) {
                NSString *uri = [d vimCurrentURI];
                if (uri.length) { prefix = [prefix stringByAppendingString:uri]; }
            }
            self.mode = VimModeCommand;
            [d vimOpenPrompt:prefix mode:VimModeCommand];
            return HBResultComplete;
        }
        case VimCmdOpenClipboard:
            [d vimOpenClipboard:[NSString stringWithFormat:@"%c", (self.reg ? self.reg : '0')]];
            return HBResultComplete;
        case VimCmdHome:
            [d vimOpenHome];
            return HBResultComplete;
        case VimCmdYank: {
            // y["x]/Y["x]: yank URI/selection into the pending register ('"' if
            // none), mirroring normal_yank -> command_yank(reg).
            unichar reg = self.reg ? self.reg : '"';
            if (c == 'Y') { [d vimYankSelection:reg]; }
            else { [d vimYankURI:reg]; }
            return HBResultComplete;
        }
        case VimCmdFocusLast:
            [d vimFocusLastActive];
            return HBResultComplete;
        case VimCmdZoom:
            // z + iIoOz: in/out/reset (normal_zoom). Uses the secondary key.
            [d vimZoomKey:k2 count:cnt];
            return HBResultComplete;
        case VimCmdQueuePop:
            // ^P: pop and load the next entry from the queue (normal_queue).
            [d vimQueuePop];
            return HBResultComplete;
        case VimCmdPrevNext:
            // GTK normal_prevnext (src/normal.c:760-776) returns RESULT_COMPLETE
            // (the hint follow-link body is #if 0), so the key is consumed.
            return HBResultComplete;
        case VimCmdG:
            return [self invokeGCmd:c k2:k2 k3:k3 cnt:cnt delegate:d];
        case VimCmdNone:
            // Unreachable in practice (checked at the call site), but listed
            // so the switch is exhaustive: adding a new VimNormalCmd without a
            // case here is a -Wswitch warning, not a silent fallthrough.
            return HBResultError;
    }
}

- (HBResult)invokeGCmd:(unichar)key k2:(unichar)k2 k3:(unichar)k3 cnt:(NSInteger)cnt delegate:(id<VimDelegate>)d {
    switch (k2) {
        case 'g':
            [d vimScrollMode:'g' count:(NSUInteger)cnt];
            return HBResultComplete;
        case 'h': case 'H':
            // gH -> home-page in a new tab, gh -> home-page in current tab.
            [d vimOpenHomePage:(k2 == 'H')];
            return HBResultComplete;
        case 'i':
            [d vimFocusInput];
            return HBResultComplete;
        case 't':
            if (cnt > 0) {
                [d vimGotoTab:(NSUInteger)(cnt - 1)];
            } else {
                [d vimNextTab];
            }
            return HBResultComplete;
        case 'T':
            if (cnt > 0) {
                // count tabs backward: from last go back (cnt-1)
                [d vimGotoTabFromLast:cnt];
            } else {
                [d vimPrevTab];
            }
            return HBResultComplete;
        case '0':
            [d vimGotoTab:0];
            return HBResultComplete;
        case '$':
            [d vimGotoTab:NSNotFound];
            return HBResultComplete;
        case 'f':
            [d vimViewSource];
            return HBResultComplete;
        case 'F':
            [d vimViewInspector];
            return HBResultComplete;
        case 'u': case 'U':
            [d vimGoHomeURL];
            return HBResultComplete;
        case ';': {
            // "g;X" g-mode hinting: keep the hints open (repeatable).
            unichar hm = k3 ? k3 : 'o';
            if (![VimbHintEngine validMode:hm gmode:YES]) {
                [d vimToggleHints];
                return HBResultComplete;
            }
            self.mode = VimModeHint;
            [d vimOpenPrompt:@"" mode:VimModeHint];
            [d vimEnterHints:[NSString stringWithFormat:@"%c", hm] gmode:YES];
            return HBResultComplete;
        }
        default:
            return HBResultError;
    }
}

@end

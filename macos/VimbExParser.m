#import "VimbExParser.h"

// ex.c ExInfo flags.
typedef NS_OPTIONS(NSUInteger, VimbExFlag) {
    VimbExFlagNone = 0x000,
    VimbExFlagBang = 0x001, /* command uses the bang ! after command name */
    VimbExFlagLhs  = 0x002, /* single word after the command name */
    VimbExFlagRhs  = 0x004, /* right hand side arg */
    VimbExFlagExp  = 0x008, /* expand pattern (% / %:p) in rhs */
    VimbExFlagCmd  = 0x010, /* like EX_FLAG_RHS but can contain | chars */
};

// One row of ex.c's commands[] table (name + flags). Dispatch codes / funcs
// are not needed here: this class only resolves and parses.
typedef struct {
    const char *name;
    VimbExFlag flags;
} VimbExCmd;

static const VimbExCmd cmds[] = {
    // command           flags
    {"autocmd",          VimbExFlagCmd | VimbExFlagBang},
    {"augroup",          VimbExFlagLhs | VimbExFlagBang},
    {"bma",              VimbExFlagRhs},
    {"bmr",              VimbExFlagRhs},
    {"cmap",             VimbExFlagLhs | VimbExFlagCmd},
    {"cnoremap",         VimbExFlagLhs | VimbExFlagCmd},
    {"cunmap",           VimbExFlagLhs},
    {"cleardata",        VimbExFlagLhs | VimbExFlagRhs},
    {"hardcopy",         VimbExFlagNone},
    {"handler-add",      VimbExFlagRhs},
    {"handler-remove",   VimbExFlagRhs},
    {"eval",             VimbExFlagCmd | VimbExFlagBang},
    {"imap",             VimbExFlagLhs | VimbExFlagCmd},
    {"inoremap",         VimbExFlagLhs | VimbExFlagCmd},
    {"iunmap",           VimbExFlagLhs},
    {"nmap",             VimbExFlagLhs | VimbExFlagCmd},
    {"nnoremap",         VimbExFlagLhs | VimbExFlagCmd},
    {"normal",           VimbExFlagBang | VimbExFlagCmd},
    {"nunmap",           VimbExFlagLhs},
    {"open",             VimbExFlagCmd},
    {"quit",             VimbExFlagNone | VimbExFlagBang},
    {"quitall",          VimbExFlagNone | VimbExFlagBang},
    {"qunshift",         VimbExFlagRhs},
    {"qclear",           VimbExFlagRhs},
    {"qpop",             VimbExFlagNone},
    {"qpush",            VimbExFlagRhs},
    {"register",         VimbExFlagNone},
    {"save",             VimbExFlagRhs | VimbExFlagExp},
    {"set",              VimbExFlagRhs},
    {"shellcmd",         VimbExFlagCmd | VimbExFlagExp | VimbExFlagBang},
    {"shellex",          VimbExFlagCmd | VimbExFlagExp},
    {"shortcut-add",     VimbExFlagRhs},
    {"shortcut-default", VimbExFlagRhs},
    {"shortcut-remove",  VimbExFlagRhs},
    {"source",           VimbExFlagRhs | VimbExFlagExp},
    {"tabopen",          VimbExFlagCmd},
    {"tabclose",         VimbExFlagNone},
    {"tabnext",          VimbExFlagNone},
    {"tabprev",          VimbExFlagNone},
    {"tabprevious",      VimbExFlagNone},
    {"tabfirst",         VimbExFlagNone},
    {"tablast",          VimbExFlagNone},
};

static NSUInteger cmdsCount(void) {
    return sizeof(cmds) / sizeof(cmds[0]);
}

// Internal readwrite redeclaration so the parser can populate the value class.
@interface VimbExArg ()
@property(nonatomic, readwrite) NSString *command;
@property(nonatomic, readwrite) NSInteger count;
@property(nonatomic, readwrite) BOOL bang;
@property(nonatomic, readwrite, nullable) NSString *lhs;
@property(nonatomic, readwrite, nullable) NSString *rhs;
@property(nonatomic, readwrite, nullable) NSString *rest;
@property(nonatomic, readwrite) BOOL unknownCommand;
@end

// Private instance API used internally (not part of the public header).
@interface VimbExParser ()
- (instancetype)initWithLine:(NSString *)line;
- (VimbExArg *)parse;
- (NSString *)parseCommandName;
- (NSString *)parseLhs;
- (void)parseRhs;
- (nullable NSString *)trimmedRestFrom:(NSUInteger)index;
- (BOOL)isDigit:(unichar)c;
@end

@implementation VimbExArg

@end

@implementation VimbExParser {
    VimbExArg *_current;
    NSString *_line;
    NSUInteger _pos;
    BOOL _isCmdList;      // parsed token is an EX_FLAG_CMD rhs (can contain |)
    VimbExFlag _flags;    // flags of the resolved command
}

+ (VimbExArg *)parseLine:(NSString *)line {
    VimbExParser *p = [[VimbExParser alloc] initWithLine:line];
    return [p parse];
}

+ (nullable NSString *)matchCommandForName:(NSString *)name {
    if (name.length == 0) { return nil; }
    // ex.c parse_command_name: first-prefix-wins. Continue while at least one
    // command keeps matching; `first` ends as the first command that matches
    // the FULL typed prefix.
    for (NSUInteger len = 1; len <= name.length; len++) {
        NSString *prefix = [name substringToIndex:len];
        NSInteger first = -1;
        for (NSUInteger i = 0; i < cmdsCount(); i++) {
            NSString *cmd = [NSString stringWithUTF8String:cmds[i].name];
            if (cmd.length >= len && [cmd rangeOfString:prefix].location == 0) {
                if (first < 0) { first = (NSInteger)i; }
            }
        }
        if (first < 0) {
            // No command matches this depth; the whole name does not match.
            return nil;
        }
        if (len == name.length) {
            return [NSString stringWithUTF8String:cmds[first].name];
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)commandNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger i = 0; i < cmdsCount(); i++) {
        [names addObject:[NSString stringWithUTF8String:cmds[i].name]];
    }
    return names;
}

+ (NSArray<NSString *> *)cleardataTypeNames {
    return @[
        @"memory-cache", @"disk-cache", @"offline-cache",
        @"session-storage", @"local-storage", @"indexeddb-databases",
        @"cookies", @"hsts-cache",
    ];
}

- (instancetype)initWithLine:(NSString *)line {
    self = [super init];
    if (self) {
        _line = line ?: @"";
        _pos = 0;
        _flags = VimbExFlagNone;
    }
    return self;
}

- (unichar)peekChar {
    if (_pos >= _line.length) { return '\0'; }
    return [_line characterAtIndex:_pos];
}

- (void)skipWhitespace {
    while (_pos < _line.length) {
        unichar c = [_line characterAtIndex:_pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            _pos++;
        } else {
            break;
        }
    }
}

// Raw substring from `index` to end, trimmed of leading whitespace; nil when
// nothing (or only whitespace) remains.
- (nullable NSString *)trimmedRestFrom:(NSUInteger)index {
    NSUInteger i = index;
    while (i < _line.length) {
        unichar c = [_line characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            i++;
        } else {
            break;
        }
    }
    if (i >= _line.length) { return nil; }
    return [_line substringFromIndex:i];
}

// ex.c parse_command_name: resolve a possibly-abbreviated name. Consumes the
// name from the line. Returns the resolved name or nil (sets unknownCommand).
- (NSString *)parseCommandName {
    NSUInteger start = _pos;
    while (_pos < _line.length) {
        unichar c = [_line characterAtIndex:_pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '!') {
            break;
        }
        _pos++;
    }
    NSString *name = [_line substringWithRange:NSMakeRange(start, _pos - start)];
    // Repeatedly consume chars and narrow the match (ex.c first-prefix-wins).
    // name is the full token; matchCommandForName already implements the rule.
    return [[self class] matchCommandForName:name];
}

- (VimbExArg *)parse {
    _current = [[VimbExArg alloc] init];
    _current.count = 0;
    _current.bang = NO;

    // Remove leading whitespace and ':' (parse_command dispatcher).
    [self skipWhitespace];
    while (_pos < _line.length && [_line characterAtIndex:_pos] == ':') {
        _pos++;
        [self skipWhitespace];
    }

    // parse_count
    if (_pos < _line.length && [self isDigit:[_line characterAtIndex:_pos]]) {
        NSInteger count = 0;
        while (_pos < _line.length && [self isDigit:[_line characterAtIndex:_pos]]) {
            count = count * 10 + ([_line characterAtIndex:_pos] - '0');
            _pos++;
        }
        _current.count = count;
    }

    [self skipWhitespace];
    NSUInteger nameStart = _pos;
    NSString *full = [self parseCommandName];
    if (!full) {
        _current.unknownCommand = YES;
        // rest = everything after the (unknown) name token, trimmed.
        _current.rest = [self trimmedRestFrom:_pos];
        return _current;
    }
    _current.command = full;
    _flags = [self.class flagsForName:full];
    (void)nameStart;

    // parse_bang (only for commands that declare EX_FLAG_BANG)
    if (_flags & VimbExFlagBang) {
        [self skipWhitespace];
        if (_pos < _line.length && [_line characterAtIndex:_pos] == '!') {
            _current.bang = YES;
            _pos++;
        }
    }

    // Record the raw remainder for the combined-arg dispatch convention.
    _current.rest = [self trimmedRestFrom:_pos];

    [self skipWhitespace];

    // parse_lhs (single word until none-escaped whitespace)
    if (_flags & VimbExFlagLhs) {
        NSString *lhs = [self parseLhs];
        if (lhs) { _current.lhs = lhs; }
    }

    [self skipWhitespace];

    // parse_rhs
    _isCmdList = (_flags & VimbExFlagCmd) != 0;
    [self parseRhs];

    return _current;
}

- (BOOL)isDigit:(unichar)c {
    return c >= '0' && c <= '9';
}

// ex.c parse_lhs: read a single word, honoring backslash-escaped spaces.
- (NSString *)parseLhs {
    if (_pos >= _line.length) { return nil; }
    NSMutableString *out = [NSMutableString string];
    while (_pos < _line.length) {
        unichar c = [_line characterAtIndex:_pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { break; }
        if (c == '\\') {
            _pos++;
            if (_pos >= _line.length) {
                [out appendString:@"\\"];
            } else {
                unichar n = [_line characterAtIndex:_pos];
                if (n == ' ') {
                    [out appendString:@" "];
                } else {
                    [out appendString:@"\\"];
                    [out appendString:[NSString stringWithFormat:@"%C", n]];
                }
            }
        } else {
            [out appendString:[NSString stringWithFormat:@"%C", c]];
        }
        _pos++;
    }
    return out.length ? out : nil;
}

// ex.c parse_rhs: read to end-of-line, or to '|' if not a command list.
// Expansion placeholders (~, $, %) are passed through verbatim here; the
// caller (VimbEx) applies page-context expansion.
- (void)parseRhs {
    if (!_isCmdList && (_flags & VimbExFlagRhs) == 0) { return; }
    if (_pos >= _line.length) { return; }
    NSMutableString *out = [NSMutableString string];
    while (_pos < _line.length) {
        unichar c = [_line characterAtIndex:_pos];
        if (c == '\n') { break; }
        if (!_isCmdList && c == '|') { break; }
        [out appendString:[NSString stringWithFormat:@"%C", c]];
        _pos++;
    }
    if (out.length) { _current.rhs = out; }
}

+ (VimbExFlag)flagsForName:(NSString *)name {
    for (NSUInteger i = 0; i < cmdsCount(); i++) {
        if ([[NSString stringWithUTF8String:cmds[i].name] isEqualToString:name]) {
            return cmds[i].flags;
        }
    }
    return VimbExFlagNone;
}

@end

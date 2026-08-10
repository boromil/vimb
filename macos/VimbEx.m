#import "VimbEx.h"

// Command descriptor mirroring ex.c's ExInfo table.
typedef NS_ENUM(NSInteger, ExCmd) {
    ExOpen, ExSet, ExQuit, ExQuitAll, ExReload, ExStop, ExTabcmd,
    ExEval, ExSave, ExRegister, ExAutocmd, ExMap, ExUnmap, ExSource,
    ExMessage, ExShortcut, ExBookmark
};

@implementation VimbEx {
    NSArray<NSArray<NSString *> *> *_table; // [name, type, ...]
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _table = @[
            @[@"autocmd", @"autocmd"],
            @[@"augroup", @"autocmd"],
            @[@"bma", @"bookmark"],
            @[@"bmr", @"bookmark"],
            @[@"cmap", @"map"], @[@"cnoremap", @"map"], @[@"cunmap", @"unmap"],
            @[@"cleardata", @"message"],
            @[@"hardcopy", @"message"],
            @[@"handler-add", @"message"], @[@"handler-remove", @"message"],
            @[@"eval", @"eval"],
            @[@"imap", @"map"], @[@"inoremap", @"map"], @[@"iunmap", @"unmap"],
            @[@"nmap", @"map"], @[@"nnoremap", @"map"], @[@"nunmap", @"unmap"],
            @[@"normal", @"eval"],
            @[@"open", @"open"],
            @[@"quit", @"quit"], @[@"quitall", @"quitall"],
            @[@"qunshift", @"message"], @[@"qclear", @"message"], @[@"qpop", @"message"], @[@"qpush", @"message"],
            @[@"register", @"register"],
            @[@"save", @"save"],
            @[@"set", @"set"],
            @[@"shellcmd", @"message"], @[@"shellex", @"message"],
            @[@"shortcut-add", @"shortcut"], @[@"shortcut-default", @"shortcut"], @[@"shortcut-remove", @"shortcut"],
            @[@"source", @"source"],
            @[@"tabopen", @"open"],
            @[@"tabclose", @"tabcmd"], @[@"tabnext", @"tabcmd"], @[@"tabprev", @"tabcmd"],
            @[@"tabprevious", @"tabcmd"], @[@"tabfirst", @"tabcmd"], @[@"tablast", @"tabcmd"],
            // short aliases commonly used
            @[@"o", @"open"], @[@"bdelete", @"tabcmd"], @[@"bd", @"tabcmd"],
            @[@"tabn", @"tabcmd"], @[@"tabp", @"tabcmd"], @[@"reload", @"open"],
            @[@"r", @"open"],
        ];
    }
    return self;
}

- (NSArray<NSString *> *)commandNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSArray<NSString *> *r in _table) {
        NSString *name = r[0];
        if (![names containsObject:name]) { [names addObject:name]; }
    }
    return names;
}

// Matches a possibly-abbreviated command name against the table.
- (NSString *)matchCommand:(NSString *)name {
    NSString *match = nil;
    for (NSArray<NSString *> *r in _table) {
        NSString *cand = r[0];
        if ([cand hasPrefix:name]) {
            if (match) { return nil; } // ambiguous
            match = cand;
        }
    }
    return match;
}

- (NSString *)expandToken:(NSString *)token {
    return token; // %/# expansion handled by caller with page context
}

- (BOOL)runCommand:(NSString *)raw {
    id<VimbExActor> a = self.actor;
    if (!a) { return NO; }

    NSString *cmdLine = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL bang = NO;
    if ([cmdLine hasPrefix:@"!"]) { bang = YES; cmdLine = [cmdLine substringFromIndex:1]; }
    // 'normal !' and 'eval !' allow bang; strip and ignore for the common ones.

    // Split command name from args (supports quoted arguments via spaces).
    NSArray<NSString *> *tokens = [self tokenize:cmdLine];
    if (tokens.count == 0) { return NO; }
    NSString *name = tokens[0];
    NSRange argRange = NSMakeRange(1, tokens.count - 1);
    NSString *arg = [[tokens subarrayWithRange:argRange] componentsJoinedByString:@" "];

    NSString *full = [self matchCommand:name];
    if (!full) {
        [a exMessage:[NSString stringWithFormat:@"Invalid command: %@", name] error:YES];
        return NO;
    }
    (void)bang;

    NSString *type = nil;
    for (NSArray<NSString *> *r in _table) { if ([r[0] isEqualToString:full]) { type = r[1]; break; } }

    if ([type isEqualToString:@"open"]) {
        BOOL newTab = [full isEqualToString:@"tabopen"];
        // "reload"/"r" reload instead of open
        if ([full isEqualToString:@"reload"] || [full isEqualToString:@"r"]) {
            [a exReload];
        } else {
            [a exOpen:arg newTab:newTab];
        }
        return NO;
    }
    if ([type isEqualToString:@"set"]) {
        [a exSet:arg];
        return NO;
    }
    if ([type isEqualToString:@"quit"]) {
        [a exQuit];
        return NO;
    }
    if ([type isEqualToString:@"quitall"]) {
        [a exQuitAll];
        return NO;
    }
    if ([type isEqualToString:@"tabcmd"]) {
        [self handleTabcmd:full arg:arg actor:a];
        return NO;
    }
    if ([type isEqualToString:@"eval"]) {
        [a exEval:[self evalArg:full arg:arg]];
        return NO;
    }
    if ([type isEqualToString:@"save"]) { [a exSavePage]; return NO; }
    if ([type isEqualToString:@"register"]) { [a exRegisterList]; return NO; }
    if ([type isEqualToString:@"autocmd"]) { [a exMessage:@"autocmd: not yet supported on native" error:YES]; return NO; }
    if ([type isEqualToString:@"map"]) { [a exMessage:@"mapping: use :nnoremap in config" error:YES]; return NO; }
    if ([type isEqualToString:@"unmap"]) { [a exMessage:@"mapping: use :nunmap in config" error:YES]; return NO; }
    if ([type isEqualToString:@"source"]) { [a exMessage:@"source: not yet supported on native" error:YES]; return NO; }
    if ([type isEqualToString:@"shortcut"]) { [a exMessage:@"shortcut: use :shortcut-add" error:YES]; return NO; }
    if ([type isEqualToString:@"bookmark"]) {
        NSString *fullName = full; // bma/bmr
        NSString *rest = arg;
        if ([fullName isEqualToString:@"bma"]) {
            // format: :bma [url [title]]  (no / with) — keep simple: url then title
            NSArray<NSString *> *p = [self tokenize:arg];
            if (p.count >= 1) {
                [a exBookmarkAdd:p[0] title:(p.count >= 2 ? p[1] : @"")];
            } else {
                [a exMessage:@"bma requires an URL" error:YES];
            }
        } else if ([fullName isEqualToString:@"bmr"]) {
            [a exBookmarkRemove:rest];
        }
        return NO;
    }
    if ([type isEqualToString:@"message"]) { [a exMessage:@"" error:NO]; return NO; }
    return NO;
}

- (NSArray<NSString *> *)tokenize:(NSString *)cmdLine {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    BOOL inQuote = NO;
    for (NSUInteger i = 0; i < cmdLine.length; i++) {
        unichar c = [cmdLine characterAtIndex:i];
        if (c == '"') { inQuote = !inQuote; if (inQuote) continue; }
        if (c == ' ' && !inQuote) {
            if (cur.length) { [tokens addObject:cur]; [cur setString:@""]; }
            continue;
        }
        [cur appendFormat:@"%C", c];
    }
    if (cur.length) { [tokens addObject:cur]; }
    return tokens;
}

- (void)handleTabcmd:(NSString *)full arg:(NSString *)arg actor:(id<VimbExActor>)a {
    if ([full isEqualToString:@"tabclose"]) { [a exCloseActiveTab]; }
    else if ([full isEqualToString:@"tabnext"] || [full isEqualToString:@"tabn"]) { [a exNextTab]; }
    else if ([full isEqualToString:@"tabprev"] || [full isEqualToString:@"tabprevious"] || [full isEqualToString:@"tabp"]) { [a exPrevTab]; }
    else if ([full isEqualToString:@"tabfirst"]) { [a exFirstTab]; }
    else if ([full isEqualToString:@"tablast"]) { [a exLastTab]; }
    else if ([full isEqualToString:@"bdelete"] || [full isEqualToString:@"bd"]) {
        [a exCloseActiveTab];
    } else {
        // buffer <n> selects a tab
        NSInteger n = arg.integerValue;
        if (n > 0) { [a exMessage:@"" error:NO]; /* tab selection is via :tabn */ }
    }
}

- (NSString *)evalArg:(NSString *)full arg:(NSString *)arg {
    // :eval <js> — pass through (bang handled upstream).
    if ([full isEqualToString:@"normal"]) {
        // :normal [cmd] — parse keys later; treat as eval no-op here.
    }
    return arg;
}

@end

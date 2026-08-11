#import "VimbEx.h"
#import "VimbConfig.h"
#import "VimbAutocmd.h"

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
            @[@"bookmarks", @"bookmarks"],
            @[@"cmap", @"map"], @[@"cnoremap", @"map"], @[@"cunmap", @"unmap"],
            @[@"cleardata", @"cleardata"],
            @[@"hardcopy", @"hardcopy"],
            @[@"handler-add", @"handler"], @[@"handler-remove", @"handler"],
            @[@"eval", @"eval"],
            @[@"imap", @"map"], @[@"inoremap", @"map"], @[@"iunmap", @"unmap"],
            @[@"nmap", @"map"], @[@"nnoremap", @"map"], @[@"nunmap", @"unmap"],
            @[@"normal", @"normal"],
            @[@"open", @"open"],
            @[@"quit", @"quit"], @[@"quitall", @"quitall"],
            @[@"qunshift", @"queue"], @[@"qclear", @"queue"], @[@"qpop", @"queue"], @[@"qpush", @"queue"],
            @[@"register", @"register"],
            @[@"save", @"save"],
            @[@"set", @"set"],
            @[@"shellcmd", @"shell"], @[@"shellex", @"shell"],
            @[@"shortcut-add", @"shortcut"], @[@"shortcut-default", @"shortcut"], @[@"shortcut-remove", @"shortcut"],
            @[@"source", @"source"],
            @[@"tabopen", @"open"],
            @[@"tabclose", @"tabcmd"], @[@"tabnext", @"tabcmd"], @[@"tabprev", @"tabcmd"],
            @[@"tabprevious", @"tabcmd"], @[@"tabfirst", @"tabcmd"], @[@"tablast", @"tabcmd"],
            // Short aliases that resolve exactly as GTK4's first-prefix abbreviation
            // (kept for clarity; no extra commands are invented beyond ex.c).
            @[@"o", @"open"],
            @[@"tabn", @"tabcmd"], @[@"tabp", @"tabcmd"],
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

// Matches a possibly-abbreviated command name against the table, mirroring
// ex.c parse_command_name: the FIRST table command whose name has the typed
// string as a prefix is selected (so ambiguous abbreviations resolve to the
// first-defined command, e.g. ":q" -> quit, ":t" -> tabopen). Returns nil
// when no command matches.
- (NSString *)matchCommand:(NSString *)name {
    if (name.length == 0) { return nil; }
    // De-duplicate aliases: prefer the longest/first full name so an exact
    // command still resolves (e.g. "open" -> open, not the "o" alias).
    NSString *result = nil;
    for (NSArray<NSString *> *r in _table) {
        NSString *cmd = r[0];
        if (cmd.length >= name.length && [cmd hasPrefix:name] && cmd.length >= name.length) {
            if (result == nil || cmd.length == name.length || result.length < cmd.length) {
                // Prefer an exact-length match, else first in table order.
                if (cmd.length == name.length) { return cmd; }
                if (result == nil) { result = cmd; }
            }
        }
    }
    return result;
}

- (NSString *)expandToken:(NSString *)token {
    return token; // %/# expansion handled by caller with page context
}

- (BOOL)runCommand:(NSString *)raw {
    id<VimbExActor> a = self.actor;
    if (!a) { return NO; }

    NSString *cmdLine = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL bang = NO;

    // Split command name from args (supports quoted arguments via spaces).
    NSArray<NSString *> *tokens = [self tokenize:cmdLine];
    if (tokens.count == 0) { return NO; }
    NSString *name = tokens[0];
    // GTK parses a post-command bang (e.g. :quit! / :eval! / :normal! gg /
    // :shellcmd! ls) for commands that declare EX_FLAG_BANG. Strip it from the
    // command name the way parse_bang() consumes it after the name.
    if (name.length > 1 && [name hasSuffix:@"!"]) {
        NSMutableArray<NSString *> *mutable = [tokens mutableCopy];
        NSString *stripped = [name substringToIndex:name.length - 1];
        if (stripped.length) {
            mutable[0] = stripped;
        } else {
            [mutable removeObjectAtIndex:0];
        }
        tokens = mutable;
        name = stripped;
        bang = YES;
    }
    NSRange argRange = NSMakeRange(1, tokens.count - 1);
    NSString *arg = [[tokens subarrayWithRange:argRange] componentsJoinedByString:@" "];

    NSString *full = [self matchCommand:name];
    if (!full) {
        // Not a recognized ex command: treat the whole line as a URL/query to
        // open (vim b) — this makes ":open foo", bare ":" URLs and prefilled
        // command lines behave consistently.
        if ([cmdLine rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location == NSNotFound
            && ![cmdLine containsString:@"/"]
            && ![cmdLine containsString:@"."]) {
            // Still ambiguous-ly not a URL (a single bare token with no dot or
            // slash); could be a typo'd command.
            [a exMessage:[NSString stringWithFormat:@"Invalid command: %@", name] error:YES];
            return NO;
        }
        [a exOpen:cmdLine newTab:NO];
        return NO;
    }
    (void)bang;

    NSString *type = nil;
    for (NSArray<NSString *> *r in _table) { if ([r[0] isEqualToString:full]) { type = r[1]; break; } }

    if ([type isEqualToString:@"open"]) {
        BOOL newTab = [full isEqualToString:@"tabopen"];
        [a exOpen:arg newTab:newTab];
        return NO;
    }
    if ([type isEqualToString:@"set"]) {
        [a exSet:arg];
        return NO;
    }
    if ([type isEqualToString:@"quit"]) {
        [a exQuit:bang];
        return NO;
    }
    if ([type isEqualToString:@"quitall"]) {
        [a exQuitAll:bang];
        return NO;
    }
    if ([type isEqualToString:@"tabcmd"]) {
        [self handleTabcmd:full arg:arg actor:a];
        return NO;
    }
    if ([type isEqualToString:@"normal"]) {
        // GTK ex_normal: enter normal mode, then feed RHS as normal keys;
        // bang (":normal!") skips mapping (map_handle_string with noremap).
        [a exNormal:arg applyMapping:!bang];
        return NO;
    }
    if ([type isEqualToString:@"eval"]) {
        [a exEval:[self evalArg:full arg:arg] suppressOutput:bang];
        return NO;
    }
    if ([type isEqualToString:@"cleardata"]) {
        // GTK: types separated by comma (lhs); '-' or empty = all. Pass the
        // raw types string through to the actor.
        [a exClearData:arg];
        return NO;
    }
    if ([type isEqualToString:@"hardcopy"]) {
        [a exPrint];
        return NO;
    }
    if ([type isEqualToString:@"handler"]) { return [self handleHandlerCommand:full arg:arg actor:a]; }
    if ([type isEqualToString:@"save"]) { [a exSavePage:arg.length ? arg : nil]; return NO; }
    if ([type isEqualToString:@"register"]) { [a exRegisterList]; return NO; }
    if ([type isEqualToString:@"autocmd"]) {
        VimbAutocmd *au = [VimbConfig shared].autocmd;
        __weak typeof(self) weakSelf = self;
        au.executor = ^(NSString *excmd) {
            [weakSelf runCommand:excmd];
        };
        au.reporter = ^(NSString *msg, BOOL error) {
            [a exMessage:msg error:error];
        };
        if ([full hasPrefix:@"augroup"]) {
            [au parseAugroupLine:arg];
        } else {
            [au parseAutocmdLine:arg];
        }
        return NO;
    }
    if ([type isEqualToString:@"map"]) { return [self handleMapCommand:full arg:arg]; }
    if ([type isEqualToString:@"unmap"]) { return [self handleUnmapCommand:full arg:arg]; }
    if ([type isEqualToString:@"source"]) {
        [a exSource:arg];
        return NO;
    }
    if ([type isEqualToString:@"shortcut"]) { return [self handleShortcutCommand:full arg:arg actor:a]; }
    if ([type isEqualToString:@"queue"]) { [a exQueue:full arg:arg]; return NO; }
    if ([type isEqualToString:@"bookmark"]) {
        // GTK ex_bookmark: :bma [tags] bookmarks the CURRENT page (RHS is only
        // tags); :bmr [match] removes by exact match, or the current page when
        // no arg is given.
        if ([full isEqualToString:@"bma"]) {
            [a exBookmarkCurrent:arg.length ? arg : nil];
        } else { // bmr
            [a exUnbookmark:arg.length ? arg : nil];
        }
        return NO;
    }
    if ([type isEqualToString:@"shell"]) { [a exShell:arg async:bang]; return NO; }
    if ([type isEqualToString:@"bookmarks"]) {
        if ([a respondsToSelector:@selector(exShowBookmarks)]) {
            [a exShowBookmarks];
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
            if (cur.length) {
                [tokens addObject:[cur copy]];
                [cur setString:@""];
            }
            continue;
        }
        [cur appendFormat:@"%C", c];
    }
    if (cur.length) { [tokens addObject:[cur copy]]; }
    return tokens;
}

- (void)handleTabcmd:(NSString *)full arg:(NSString *)arg actor:(id<VimbExActor>)a {
    if ([full isEqualToString:@"tabclose"]) { [a exCloseActiveTab]; }
    else if ([full isEqualToString:@"tabnext"] || [full isEqualToString:@"tabn"]) { [a exNextTab]; }
    else if ([full isEqualToString:@"tabprev"] || [full isEqualToString:@"tabprevious"] || [full isEqualToString:@"tabp"]) { [a exPrevTab]; }
    else if ([full isEqualToString:@"tabfirst"]) { [a exFirstTab]; }
    else if ([full isEqualToString:@"tablast"]) { [a exLastTab]; }
    else {
        // buffer <n> selects a tab
        NSInteger n = arg.integerValue;
        if (n > 0) { [a exMessage:@"" error:NO]; /* tab selection is via :tabn */ }
    }
}

- (NSString *)evalArg:(NSString *)full arg:(NSString *)arg {
    return arg;
}

// :handler-add <scheme>=<command> / :handler-remove <scheme> (GTK ex_handlers).
- (BOOL)handleHandlerCommand:(NSString *)full arg:(NSString *)arg actor:(id<VimbExActor>)a {
    if ([full isEqualToString:@"handler-add"]) {
        NSRange eq = [arg rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) {
            [a exMessage:@"handler-add requires scheme=command" error:YES];
            return NO;
        }
        NSString *scheme = [arg substringToIndex:eq.location];
        NSString *command = [arg substringFromIndex:(eq.location + 1)];
        scheme = [scheme stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (scheme.length == 0 || command.length == 0) {
            [a exMessage:@"handler-add requires scheme=command" error:YES];
            return NO;
        }
        __weak typeof(a) weakA = a;
        [a exHandlerAdd:scheme command:command success:^(BOOL ok) {
            if (!ok) {
                [weakA exMessage:@"failed to add handler" error:YES];
            }
        }];
        return NO;
    }
    NSString *scheme = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (scheme.length == 0) {
        [a exMessage:@"handler-remove requires a scheme" error:YES];
        return NO;
    }
    __weak typeof(a) weakA = a;
    [a exHandlerRemove:scheme success:^(BOOL ok) {
        if (!ok) {
            [weakA exMessage:@"handler not found" error:YES];
        }
    }];
    return NO;
}

// Maps the ex command name to its mapping mode char.
- (NSString *)mapModeForCommand:(NSString *)name {
    if ([name hasPrefix:@"n"]) { return @"n"; }   // nmap / nnoremap / nunmap
    if ([name hasPrefix:@"i"]) { return @"i"; }   // imap / inoremap / iunmap
    if ([name hasPrefix:@"c"]) { return @"c"; }   // cmap / cnoremap / cunmap
    return @"n";
}

- (BOOL)isNoremapCommand:(NSString *)name {
    return [name containsString:@"noremap"];
}

- (BOOL)handleUnmapCommand:(NSString *)full arg:(NSString *)arg {
    NSString *mode = [self mapModeForCommand:full];
    NSString *lhs = [[VimbConfig shared] convertKeyString:
        [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    if (lhs.length == 0) {
        [self.actor exMessage:@"unmap requires a key" error:YES];
        return NO;
    }
    BOOL removed = [[VimbConfig shared] removeMappingForMode:mode lhs:lhs];
    if (!removed) {
        // Not an error in vim; keep the command line quiet as vimb does.
    }
    return NO;
}

// :shortcut-add <name> <url> / :shortcut-default <name> / :shortcut-remove <name>
- (BOOL)handleShortcutCommand:(NSString *)full arg:(NSString *)arg actor:(id<VimbExActor>)a {
    if ([full isEqualToString:@"shortcut-add"]) {
        NSArray<NSString *> *p = [self tokenize:arg];
        if (p.count < 1) {
            [a exMessage:@"shortcut-add requires a name and a url" error:YES];
            return NO;
        }
        NSString *key = p[0];
        // The url is the remainder of the line (may contain spaces). Accept
        // both "name url" and vimb's legacy "name=url" syntax.
        NSString *rest = arg.length > key.length ? [arg substringFromIndex:key.length] : @"";
        rest = [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([rest hasPrefix:@"="]) { rest = [rest substringFromIndex:1]; }
        NSString *url = [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length == 0 || url.length == 0) {
            [a exMessage:@"shortcut-add requires a name and a url" error:YES];
            return NO;
        }
        [VimbConfig shared].shortcuts[key] = url;
        [a exMessage:[NSString stringWithFormat:@"shortcut %@ = %@", key, url] error:NO];
    } else {
        NSString *key = [arg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length == 0) {
            [a exMessage:[full containsString:@"remove"]
                ? @"shortcut-remove requires a name"
                : @"shortcut-default requires a name" error:YES];
            return NO;
        }
        if ([full isEqualToString:@"shortcut-default"]) {
            [VimbConfig shared].defaultShortcut = key;
            // The default opened page follows the selected search engine.
            [VimbConfig shared].settings[@"home-page"] =
                [[VimbConfig shared] searchEngineMainPage];
            [a exMessage:[NSString stringWithFormat:@"default shortcut is %@", key] error:NO];
        } else { // shortcut-remove
            BOOL removed = [VimbConfig shared].shortcuts[key] != nil;
            [[VimbConfig shared].shortcuts removeObjectForKey:key];
            [a exMessage:removed ? @"shortcut removed" : @"shortcut not found" error:!removed];
        }
    }
    return NO;
}

- (BOOL)handleMapCommand:(NSString *)full arg:(NSString *)arg {
    NSString *mode = [self mapModeForCommand:full];
    BOOL noremap = [self isNoremapCommand:full];

    NSArray<NSString *> *parts = [self tokenize:arg];
    if (parts.count < 2) {
        [self.actor exMessage:@"map requires a lhs and a rhs" error:YES];
        return NO;
    }
    NSString *lhs = [[VimbConfig shared] convertKeyString:parts[0]];
    // rhs keeps its original spacing (may contain spaces / ex command).
    NSString *rawRhs = [arg substringFromIndex:parts[0].length];
    rawRhs = [rawRhs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *rhs = [[VimbConfig shared] convertKeyString:rawRhs];

    if (lhs.length == 0 || rhs.length == 0) {
        [self.actor exMessage:@"map requires a non-empty lhs and rhs" error:YES];
        return NO;
    }
    [[VimbConfig shared] addMappingForMode:mode lhs:lhs rhs:rhs noremap:noremap];
    return NO;
}

@end

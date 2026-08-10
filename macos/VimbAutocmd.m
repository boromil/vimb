#import "VimbAutocmd.h"

NS_ASSUME_NONNULL_BEGIN

@interface AuEntry : NSObject
@property(nonatomic, copy) NSString *pattern;
@property(nonatomic, copy) NSString *excmd;
@property(nonatomic, assign) VAuEvent event;
@end

@implementation AuEntry
@end

static VAuEvent eventFromName(NSString *name) {
    name = [name lowercaseString];
    if ([name isEqualToString:@"load-starting"])      { return VAuLoadStarting; }
    if ([name isEqualToString:@"load-started"])       { return VAuLoadStarted; }
    if ([name isEqualToString:@"load-committed"])     { return VAuLoadCommitted; }
    if ([name isEqualToString:@"load-finished"])      { return VAuLoadFinished; }
    if ([name isEqualToString:@"download-started"])   { return VAuDownloadStarted; }
    if ([name isEqualToString:@"download-finished"])  { return VAuDownloadFinished; }
    if ([name isEqualToString:@"download-failed"])    { return VAuDownloadFailed; }
    if ([name isEqualToString:@"all"])                { return VAuAll; }
    return (VAuEvent)-1;
}

static NSString *eventName(VAuEvent e) {
    switch (e) {
        case VAuLoadStarting:   return @"load-starting";
        case VAuLoadStarted:    return @"load-started";
        case VAuLoadCommitted:  return @"load-committed";
        case VAuLoadFinished:   return @"load-finished";
        case VAuDownloadStarted:return @"download-started";
        case VAuDownloadFinished:return @"download-finished";
        case VAuDownloadFailed: return @"download-failed";
        case VAuAll:            return @"all";
        default:                return @"";
    }
}

@implementation VimbAutocmd {
    NSMutableArray<AuEntry *> *_entries;
    NSString *_curGroup;
    BOOL _curGroupEsc;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _curGroup = @"";
        _curGroupEsc = NO;
    }
    return self;
}

- (BOOL)parseAugroupLine:(NSString *)line {
    // :augroup {name} | :augroup! {name} | :augroup END
    NSCharacterSet *sp = [NSCharacterSet whitespaceCharacterSet];
    line = [line stringByTrimmingCharactersInSet:sp];
    BOOL bang = NO;
    if ([line hasPrefix:@"!"]) { bang = YES; line = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:sp]; }
    NSArray *parts = [line componentsSeparatedByCharactersInSet:sp];
    if (parts.count == 0) {
        _curGroupEsc = YES;
        if (self.reporter) self.reporter(@"augroup: closing pending group", NO);
        return YES;
    }
    NSString *name = parts[0];
    if ([[name uppercaseString] isEqualToString:@"END"]) {
        _curGroupEsc = bang;
    } else {
        _curGroup = name;
        _curGroupEsc = bang;
    }
    return YES;
}

- (BOOL)parseAutocmdLine:(NSString *)line {
    // :autocmd [group] {event} {pat} :{cmd}   or  :autocmd! ...
    NSCharacterSet *sp = [NSCharacterSet whitespaceCharacterSet];
    line = [line stringByTrimmingCharactersInSet:sp];
    BOOL bang = NO;
    if ([line hasPrefix:@"!"]) { bang = YES; line = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:sp]; }

    // Tokenize; handle the trailing :command which may contain spaces.
    NSMutableArray *tokens = [NSMutableArray array];
    NSMutableArray *cmdParts = [NSMutableArray array];
    BOOL inCmd = NO;
    NSScanner *scan = [NSScanner scannerWithString:line];
    while (!scan.isAtEnd) {
        NSString *word;
        if ([scan scanUpToCharactersFromSet:sp intoString:&word]) {
            if (inCmd) {
                [cmdParts addObject:word];
            } else if ([word hasPrefix:@":"]) {
                inCmd = YES;
                [cmdParts addObject:word];
            } else {
                [tokens addObject:word];
            }
        }
        if (inCmd) { /* keep scanning; spaces separate cmd words */ }
    }

    if (cmdParts.count == 0) {
        if (self.reporter) self.reporter(@"autocmd: missing command", YES);
        return YES;
    }

    // tokens[0] may be a group name (if != current group and known), else event.
    NSString *eventWord = nil;
    NSString *pattern = @"*";
    NSUInteger idx = 0;
    if (bang && tokens.count >= 1) {
        // delete: :autocmd! event [pat]  (pattern optional)
        eventWord = tokens[0];
        if (tokens.count > 1) { pattern = tokens[1]; }
        [self removeEvent:[self nameToEvent:eventWord] pattern:pattern];
        if (self.reporter) self.reporter(@"autocmd: removed", NO);
        return YES;
    }

    if (tokens.count >= 1) { eventWord = tokens[idx]; idx++; }
    if (tokens.count >= 2) { pattern = tokens[idx]; }

    VAuEvent event = [self nameToEvent:eventWord];
    if (event == (VAuEvent)-1) {
        if (self.reporter) self.reporter([NSString stringWithFormat:@"autocmd: bad event '%@'", eventWord], YES);
        return YES;
    }

    NSString *excmd = [cmdParts componentsJoinedByString:@" "];
    if ([excmd hasPrefix:@":"]) { excmd = [excmd substringFromIndex:1]; }

    AuEntry *en = [[AuEntry alloc] init];
    en.event = event;
    en.pattern = pattern;
    en.excmd = excmd;
    [_entries addObject:en];
    if (self.reporter) self.reporter([NSString stringWithFormat:@"autocmd %@ %@ -> %@", eventName(event), pattern, excmd], NO);
    return YES;
}

- (VAuEvent)nameToEvent:(NSString *)name {
    return eventFromName(name ?: @"");
}

- (void)removeEvent:(VAuEvent)event pattern:(NSString *)pattern {
    NSMutableArray *keep = [NSMutableArray array];
    for (AuEntry *en in _entries) {
        if (en.event == event && [en.pattern isEqualToString:pattern]) { continue; }
        [keep addObject:en];
    }
    _entries = keep;
}

- (BOOL)hasEvent:(VAuEvent)event {
    if (_entries.count == 0) { return NO; }
    return YES;
}

- (void)fireEvent:(VAuEvent)event uri:(nullable NSString *)uri {
    if (self.executor == nil) { return; }
    for (AuEntry *en in [_entries copy]) {
        if (en.event == event || en.event == VAuAll) {
            // Simple wildcard match.
            if ([self wildcard:en.pattern match:uri]) {
                self.executor(en.excmd);
            }
        }
    }
}

- (BOOL)wildcard:(NSString *)pat match:(NSString *)uri {
    if (!uri) { uri = @""; }
    if ([pat isEqualToString:@"*"]) { return YES; }
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:[self globToRegex:pat] options:0 error:nil];
    return re ? [re numberOfMatchesInString:uri options:0 range:NSMakeRange(0, uri.length)] > 0 : NO;
}

- (NSString *)globToRegex:(NSString *)glob {
    NSMutableString *re = [NSMutableString stringWithString:@"^"];
    for (NSUInteger i = 0; i < glob.length; i++) {
        unichar c = [glob characterAtIndex:i];
        if (c == '*') { [re appendString:@".*"]; }
        else if (c == '?') { [re appendString:@"."]; }
        else { [re appendFormat:@"%C", c]; }
    }
    [re appendString:@"$"];
    return re;
}

@end

NS_ASSUME_NONNULL_END

// Foundation-only implementation of the completion candidate engine (parity
// with src/completion.c two-column items + util.c/util_fill_completion and
// setting.c/setting_fill_completion prefix matching + ex.c sorting).
#import "CompletionCandidate.h"
#include <regex.h>

@implementation CompletionCandidate

- (instancetype)initWithValue:(NSString *)value detail:(nullable NSString *)detail {
    self = [super init];
    if (self) {
        _value = [value copy];
        _detail = [detail copy];
    }
    return self;
}

+ (instancetype)candidateWithValue:(NSString *)value detail:(nullable NSString *)detail {
    return [[self alloc] initWithValue:value detail:detail];
}

- (NSString *)description {
    return self.detail.length > 0 ? [NSString stringWithFormat:@"<%@|%@>", self.value, self.detail] : self.value;
}

@end

@implementation CompletionStyle

+ (instancetype)emptyStyle {
    return [[self alloc] init];
}

- (void)setBackgroundColorRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    _hasBackground = YES;
    _bgRed = r; _bgGreen = g; _bgBlue = b; _bgAlpha = a;
}
- (void)setForegroundColorRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    _hasForeground = YES;
    _fgRed = r; _fgGreen = g; _fgBlue = b; _fgAlpha = a;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CompletionStyle bg=%d(%g,%g,%g,%g) fg=%d(%g,%g,%g,%g)>",
        self.hasBackground, self.bgRed, self.bgGreen, self.bgBlue, self.bgAlpha,
        self.hasForeground, self.fgRed, self.fgGreen, self.fgBlue, self.fgAlpha];
}

@end

@implementation CompletionMatcher

// Parse a comma-separated numeric color list like "255, 0, 0" or "1,0,0,0.5".
static BOOL parseColorList(NSString *list,
                           CGFloat *outRed, CGFloat *outGreen,
                           CGFloat *outBlue, CGFloat *outAlpha) {
    NSArray<NSString *> *components = [list componentsSeparatedByString:@","];
    if (components.count < 3 || components.count > 4) { return NO; }
    CGFloat rgba[4] = {0, 0, 0, 1};
    for (NSUInteger i = 0; i < components.count; i++) {
        NSString *part = [components[i] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Strip any trailing ) and leading or trailing %.
        if (part.length && [part characterAtIndex:part.length - 1] == ')') {
            part = [part substringToIndex:part.length - 1];
        }
        part = [part stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (part.length == 0) { return NO; }
        if ([part hasSuffix:@"%"]) {
            rgba[i] = (CGFloat)[part substringToIndex:part.length - 1].doubleValue / 100.0;
        } else {
            rgba[i] = (CGFloat)[part doubleValue];
        }
    }
    // Normalize: components may be 0..255 (CSS rgb) or already 0..1.
    BOOL is255 = (rgba[0] > 1.0 || rgba[1] > 1.0 || rgba[2] > 1.0);
    if (is255) {
        rgba[0] /= 255.0; rgba[1] /= 255.0; rgba[2] /= 255.0;
    }
    *outRed = rgba[0]; *outGreen = rgba[1]; *outBlue = rgba[2]; *outAlpha = rgba[3];
    return YES;
}

// Minimal CSS color parser supporting named rgb/rgba and #hex / #rgb /
// #rrggbbaa forms. Returns NO when the declaration is not a color.
static BOOL parseColorLiteral(NSString *_Nullable literal,
                              CGFloat *outRed, CGFloat *outGreen,
                              CGFloat *outBlue, CGFloat *outAlpha) {
    if (literal.length == 0) { return NO; }
    NSString *s = [literal stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Handle func forms: rgb(...) / rgba(...) — pull out the inner list.
    if ([s hasPrefix:@"rgb"] || [s hasPrefix:@"rgba"]) {
        NSRange paren = [s rangeOfString:@"("];
        if (paren.location != NSNotFound && [s hasSuffix:@")"]) {
            NSString *inner = [s substringFromIndex:paren.location + 1];
            inner = [inner substringToIndex:inner.length - 1]; // drop trailing )
            return parseColorList(inner, outRed, outGreen, outBlue, outAlpha);
        }
    }
    if ([s hasPrefix:@"#"]) {
        s = [s substringFromIndex:1];
        NSUInteger len = s.length;
        if (len != 3 && len != 6 && len != 8) { return NO; }
        regex_t reg;
        if (regcomp(&reg, "^[0-9a-fA-F]+$", REG_EXTENDED) != 0) { return NO; }
        BOOL ok = (regexec(&reg, s.UTF8String, 0, NULL, 0) == 0);
        regfree(&reg);
        if (!ok) { return NO; }

        NSString *expanded;
        if (len == 3) {
            NSMutableString *m = [NSMutableString string];
            for (NSUInteger i = 0; i < 3; i++) {
                NSString *c = [s substringWithRange:NSMakeRange(i, 1)];
                [m appendString:[NSString stringWithFormat:@"%@%@", c, c]];
            }
            expanded = m; // #rgb -> #rrggbb
        } else {
            expanded = s;
        }
        NSUInteger bytes = (len == 8) ? 4 : 3;
        unsigned vals[4] = {0, 0, 0, 0};
        for (NSUInteger i = 0; i < bytes; i++) {
            NSScanner *scan = [NSScanner scannerWithString:[expanded substringWithRange:NSMakeRange(i * 2, 2)]];
            unsigned int n = 0;
            if (![scan scanHexInt:&n]) { return NO; }
            vals[i] = (unsigned)n;
        }
        *outRed   = vals[0] / 255.0;
        *outGreen = vals[1] / 255.0;
        *outBlue  = vals[2] / 255.0;
        *outAlpha = (bytes == 4) ? vals[3] / 255.0 : 1.0;
        return YES;
    }
    return NO;
}

static NSString *valueForDeclaration(NSString *css, NSString *name) {
    // Split on ';' and look for "name:value".
    for (NSString *decl in [css componentsSeparatedByString:@";"]) {
        NSString *trimmed = [decl stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange colon = [trimmed rangeOfString:@":"];
        if (colon.location == NSNotFound) { continue; }
        NSString *prop = [[trimmed substringToIndex:colon.location] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([prop isEqualToString:name]) {
            return [trimmed substringFromIndex:colon.location + 1];
        }
    }
    return nil;
}

+ (CompletionStyle *)styleFromCSS:(NSString *)css {
    CompletionStyle *style = [CompletionStyle emptyStyle];
    if (css.length == 0) { return style; }

    NSString *bg = valueForDeclaration(css, @"background-color");
    if (!bg) { bg = valueForDeclaration(css, @"background"); }
    if (bg) {
        CGFloat r, g, b, a;
        if (parseColorLiteral(bg, &r, &g, &b, &a)) {
            [style setBackgroundColorRed:r green:g blue:b alpha:a];
        }
    }

    NSString *fg = valueForDeclaration(css, @"color");
    if (fg) {
        CGFloat r, g, b, a;
        if (parseColorLiteral(fg, &r, &g, &b, &a)) {
            [style setForegroundColorRed:r green:g blue:b alpha:a];
        }
    }
    return style;
}

// Rank function: prefix matches score lowest (best), any substring match next.
static NSInteger rankForMatch(NSString *query, NSString *candidate) {
    NSRange p = [candidate rangeOfString:query options:NSCaseInsensitiveSearch];
    if (p.location == 0) { return 0; }         // exact prefix
    if (p.location != NSNotFound) { return 1; } // substring
    return 2;                                   // no match
}

+ (NSArray<NSString *> *)rankMatchesForQuery:(NSString *)query
                                   inStrings:(NSArray<NSString *> *)strings
                                        limit:(NSUInteger)limit
                                       sorted:(BOOL)sorted {
    NSString *q = query ?: @"";
    NSMutableArray<NSDictionary<NSString *, id> *> *filtered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *candidate in strings) {
        if (candidate.length == 0) { continue; }
        if ([seen containsObject:candidate]) { continue; }
        // Empty query matches everything (parity with util_fill_completion /
        // setting_fill_completion: "if no filter input given - copy all").
        NSUInteger rank = (q.length == 0) ? 0 : rankForMatch(q, candidate);
        if (q.length != 0 && rank == 2) { continue; }
        [seen addObject:candidate];
        [filtered addObject:@{ @"s": candidate, @"r": @(rank) }];
    }

    // Stable: when sorted, order by rank first then lexicographically (ex.c
    // sort=TRUE). When not sorted, preserve source order (history completion).
    if (sorted) {
        NSComparator byValueSorted = ^NSComparisonResult(NSDictionary<NSString *, id> *a, NSDictionary<NSString *, id> *b) {
            NSComparisonResult byRank = [a[@"r"] compare:b[@"r"]];
            if (byRank != NSOrderedSame) { return byRank; }
            return [(NSString *)a[@"s"] compare:(NSString *)b[@"s"] options:NSCaseInsensitiveSearch];
        };
        [filtered sortUsingComparator:byValueSorted];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < filtered.count && (limit == 0 || i < limit); i++) {
        [result addObject:filtered[i][@"s"]];
    }
    return result;
}

+ (NSArray<CompletionCandidate *> *)candidatesForQuery:(NSString *)query
                                             inStrings:(NSArray<NSString *> *)strings
                                                  limit:(NSUInteger)limit
                                                 sorted:(BOOL)sorted {
    NSArray<NSString *> *matches = [self rankMatchesForQuery:query inStrings:strings limit:limit sorted:sorted];
    NSMutableArray<CompletionCandidate *> *cands = [NSMutableArray array];
    for (NSString *m in matches) {
        [cands addObject:[CompletionCandidate candidateWithValue:m detail:nil]];
    }
    return cands;
}

+ (NSArray<CompletionCandidate *> *)candidatesForQuery:(NSString *)query
                                               entries:(NSArray<NSDictionary<NSString *, NSString *> *> *)entries
                                                  limit:(NSUInteger)limit {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSDictionary *e in entries) {
        NSString *v = e[@"value"];
        if (v.length > 0) { [values addObject:v]; }
    }
    NSArray<NSString *> *matched = [self rankMatchesForQuery:query inStrings:values limit:limit sorted:YES];
    NSMutableDictionary<NSString *, NSDictionary *> *byValue = [NSMutableDictionary dictionary];
    for (NSDictionary *e in entries) { byValue[e[@"value"]] = e; }
    NSMutableArray<CompletionCandidate *> *cands = [NSMutableArray array];
    for (NSString *m in matched) {
        [cands addObject:[CompletionCandidate candidateWithValue:m detail:byValue[m][@"detail"]]];
    }
    return cands;
}

@end

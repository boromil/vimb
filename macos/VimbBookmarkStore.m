#import "VimbBookmarkStore.h"

@implementation VimbBookmark

- (instancetype)initWithURL:(NSString *)url title:(NSString *_Nullable)title tags:(NSString *_Nullable)tags {
    self = [super init];
    if (self) {
        _url = [url copy];
        _title = [title copy];
        _tags = [tags copy];
    }
    return self;
}

@end

@implementation VimbBookmarkStore

+ (instancetype)storeInTempDirectoryWithName:(NSString *)name {
    NSString *base = NSTemporaryDirectory();
    NSString *dir = [[[base stringByAppendingPathComponent:@"vimb-tests"]
                      stringByAppendingPathComponent:name] stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *file = [dir stringByAppendingPathComponent:@"bookmarks"];
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    return [[VimbBookmarkStore alloc] initWithPath:file];
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
    }
    return self;
}

// Split one bookmark file line into (url, title, tags). Returns nil for blank
// lines. Handles both tab-separated (canonical vimb) and space-separated
// (legacy macOS :bma) encodings.
+ (nullable VimbBookmark *)parseLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) { return nil; }

    if ([line containsString:@"\t"]) {
        NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count == 0 || parts[0].length == 0) { return nil; }
        NSString *url = parts[0];
        NSString *title = parts.count >= 2 ? parts[1] : @"";
        NSString *tags = parts.count >= 3 ? parts[2] : nil;
        if (title.length == 0) { title = nil; }
        if (tags.length == 0)  { tags = nil; }
        return [[VimbBookmark alloc] initWithURL:url title:title tags:tags];
    }

    // No tab: either `uri` alone or the legacy space-separated `uri title`.
    NSString *line2 = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange space = [line2 rangeOfString:@" "];
    if (space.location == NSNotFound) {
        return [[VimbBookmark alloc] initWithURL:line2 title:nil tags:nil];
    }
    NSString *url = [line2 substringToIndex:space.location];
    NSString *title = [[line2 substringFromIndex:space.location + 1]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [[VimbBookmark alloc] initWithURL:url title:(title.length ? title : nil) tags:nil];
}

- (NSArray<NSString *> *)lines {
    NSString *content = [NSString stringWithContentsOfFile:self.path
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (!content) { return @[]; }
    NSArray<NSString *> *raw = [content componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *l in raw) {
        if ([l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) {
            [out addObject:l];
        }
    }
    return out;
}

- (NSArray<VimbBookmark *> *)allBookmarks {
    NSMutableArray<VimbBookmark *> *out = [NSMutableArray array];
    for (NSString *line in [self lines]) {
        VimbBookmark *bm = [VimbBookmarkStore parseLine:line];
        if (bm) { [out addObject:bm]; }
    }
    return out;
}

- (nullable VimbBookmark *)bookmarkForURL:(NSString *)url {
    for (VimbBookmark *bm in self.allBookmarks) {
        if ([bm.url isEqualToString:url]) { return bm; }
    }
    return nil;
}

- (BOOL)containsBookmarkForURL:(NSString *)url {
    return [self bookmarkForURL:url] != nil;
}

// Parity with bookmark_contains_all_tags(): every whitespace-separated query
// part must be a prefix of some token of the tags, or of the url path when
// there are no tags, or of the title. Case-insensitive.
+ (BOOL)bookmark:(VimbBookmark *)bm matchesQueryParts:(NSArray<NSString *> *)parts {
    if (parts.count == 0) { return YES; }
    for (NSString *part in parts) {
        NSString *lower = part.lowercaseString;
        BOOL found = NO;
        NSString *title = bm.title ?: @"";
        if ([title.lowercaseString containsString:lower]) { found = YES; }

        if (!found && bm.tags.length) {
            for (NSString *tag in [bm.tags componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
                if (tag.length && [tag.lowercaseString hasPrefix:lower]) { found = YES; break; }
            }
        } else if (!found) {
            // No tags: match prefixes of url path segments (split on . and /).
            NSCharacterSet *seps = [NSCharacterSet characterSetWithCharactersInString:@"./"];
            for (NSString *tok in [bm.url componentsSeparatedByCharactersInSet:seps]) {
                if (tok.length && [tok.lowercaseString hasPrefix:lower]) { found = YES; break; }
            }
        }
        if (!found) { return NO; }
    }
    return YES;
}

- (NSArray<VimbBookmark *> *)bookmarksMatching:(NSString *)query {
    NSArray<NSString *> *parts = [[query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                  filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSMutableArray<VimbBookmark *> *out = [NSMutableArray array];
    for (VimbBookmark *bm in self.allBookmarks) {
        if ([VimbBookmarkStore bookmark:bm matchesQueryParts:parts]) { [out addObject:bm]; }
    }
    return out;
}

// Append a bookmark, skipping duplicates of an existing URL (mirrors :bma
// reordering to the front in the presence of an existing entry).
- (BOOL)addBookmarkWithURL:(NSString *)url title:(NSString *_Nullable)title tags:(NSString *_Nullable)tags {
    if (!url.length) { return NO; }
    // Keep the store unique on URL: remove an existing entry first.
    NSMutableArray<NSString *> *remaining = [self linesDroppingURL:url];
    NSString *line;
    if (tags.length) {
        line = [NSString stringWithFormat:@"%@\t%@\t%@", url, title ?: @"", tags];
    } else if (title.length) {
        line = [NSString stringWithFormat:@"%@\t%@", url, title];
    } else {
        line = url;
    }
    [remaining insertObject:line atIndex:0];
    return [self writeLines:remaining];
}

- (BOOL)removeBookmarkForURL:(NSString *)url {
    NSArray<NSString *> *original = [self lines];
    NSArray<NSString *> *reduced = [self linesDroppingURL:url];
    if (reduced.count == original.count) { return NO; }
    return [self writeLines:reduced];
}

- (NSMutableArray<NSString *> *)linesDroppingURL:(NSString *)url {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *line in [self lines]) {
        NSString *u = [VimbBookmarkStore urlOfLine:line];
        if (u && [u isEqualToString:url]) { continue; }
        [out addObject:line];
    }
    return out;
}

+ (nullable NSString *)urlOfLine:(NSString *)line {
    if ([line containsString:@"\t"]) {
        return [[line componentsSeparatedByString:@"\t"] firstObject];
    }
    NSRange space = [line rangeOfString:@" "];
    if (space.location == NSNotFound) { return line; }
    return [line substringToIndex:space.location];
}

- (BOOL)writeLines:(NSArray<NSString *> *)lines {
    NSString *joined = [lines componentsJoinedByString:@"\n"];
    if (joined.length) { joined = [joined stringByAppendingString:@"\n"]; }
    return [joined writeToFile:self.path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end

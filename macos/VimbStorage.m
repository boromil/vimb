#import "VimbStorage.h"

@implementation VimbStorage

+ (NSString *)appSupportDir {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSHomeDirectory();
    NSString *dir = [[base stringByAppendingPathComponent:@"vimb"] stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSString *)cacheDir {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSHomeDirectory();
    NSString *dir = [[base stringByAppendingPathComponent:@"vimb"] stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (instancetype)initWithName:(NSString *)name {
    return [self initWithName:name directory:[VimbStorage appSupportDir]];
}

- (instancetype)initWithName:(NSString *)name directory:(NSString *)baseDir {
    self = [super init];
    if (self) {
        NSString *dir = [baseDir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        _dir = dir;
    }
    return self;
}

+ (VimbStorage *)storageInTempDirectoryWithName:(NSString *)name {
    NSString *base = NSTemporaryDirectory();
    NSString *baseDir = [[base stringByAppendingPathComponent:@"vimb-tests"]
                         stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:baseDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [[VimbStorage alloc] initWithName:name directory:baseDir];
}

- (NSArray<NSString *> *)lines {
    NSString *content = [NSString stringWithContentsOfFile:self.dir encoding:NSUTF8StringEncoding error:nil];
    if (!content) { return @[]; }
    NSMutableArray *r = [NSMutableArray array];
    for (NSString *l in [content componentsSeparatedByString:@"\n"]) {
        if (l.length) { [r addObject:l]; }
    }
    return r;
}

- (void)writeAll:(NSArray<NSString *> *)lines {
    NSString *joined = [lines componentsJoinedByString:@"\n"];
    if (joined.length) { joined = [joined stringByAppendingString:@"\n"]; }
    [joined writeToFile:self.dir atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)prepend:(NSString *)line max:(NSUInteger)max {
    NSMutableArray *ls = [self.lines mutableCopy];
    [ls removeObject:line];
    [ls insertObject:line atIndex:0];
    if (max > 0 && ls.count > max) { [ls removeObjectsInRange:NSMakeRange(max, ls.count - max)]; }
    [self writeAll:ls];
}

- (void)append:(NSString *)line {
    NSMutableArray *ls = [self.lines mutableCopy];
    [ls addObject:line];
    [self writeAll:ls];
}

- (void)push:(NSString *)line max:(NSUInteger)max {
    [self prepend:line max:max];
}

- (nullable NSString *)top {
    return self.lines.firstObject;
}

- (void)removeLine:(NSString *)line {
    NSMutableArray *ls = [self.lines mutableCopy];
    [ls removeObject:line];
    [self writeAll:ls];
}

- (nullable NSString *)popLast {
    NSMutableArray *ls = [self.lines mutableCopy];
    if (ls.count == 0) { return nil; }
    NSString *last = ls[0];
    [ls removeObjectAtIndex:0];
    [self writeAll:ls];
    return last;
}

- (void)clear {
    [[NSFileManager defaultManager] removeItemAtPath:self.dir error:nil];
}

@end

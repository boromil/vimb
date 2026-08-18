#import "VimbHandler.h"
#import "VimbTaskRunner.h"

@implementation VimbHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _table = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)addScheme:(NSString *)scheme command:(NSString *)command {
    if (scheme.length == 0) { return NO; }
    self.table[scheme] = command;
    return YES;
}

- (BOOL)removeScheme:(NSString *)scheme {
    if (self.table[scheme]) {
        [self.table removeObjectForKey:scheme];
        return YES;
    }
    return NO;
}

- (nullable NSString *)commandForURI:(NSString *)uri {
    NSRange colon = [uri rangeOfString:@":"];
    if (colon.location == NSNotFound) { return nil; }
    NSString *scheme = [uri substringToIndex:colon.location];
    return self.table[scheme];
}

+ (NSString *)expandCommand:(NSString *)command forURI:(NSString *)uri {
    // Kept for API compatibility with tests; quoting now lives in
    // VimbTaskRunner expandTemplate:value: (single source of truth).
    return [VimbTaskRunner expandTemplate:command value:uri];
}

- (BOOL)handleURI:(NSString *)uri {
    NSString *cmd = [self commandForURI:uri];
    if (!cmd) { return NO; }

    // Substitute the URI for '%s' (g_strdup_printf in src/handler.c:73),
    // shell-quoted so a crafted URI cannot inject commands; else append it.
    NSString *expanded = [VimbTaskRunner expandTemplate:cmd value:uri];

    // Run via /bin/sh -c (asynchronously) for %s-style command templates.
    return [VimbTaskRunner runAsync:expanded environment:nil error:nil];
}

- (NSArray<NSString *> *)schemes {
    return self.table.allKeys;
}

@end

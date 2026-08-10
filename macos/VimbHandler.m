#import "VimbHandler.h"

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

- (BOOL)handleURI:(NSString *)uri {
    NSString *cmd = [self commandForURI:uri];
    if (!cmd) { return NO; }

    // Substitute the URI for the first '%s', else append it.
    NSString *expanded = cmd;
    if ([cmd containsString:@"%s"]) {
        expanded = [cmd stringByReplacingOccurrencesOfString:@"%s"
                                                  withString:uri
                                                     options:0
                                                       range:[cmd rangeOfString:@"%s"]];
    } else {
        expanded = [NSString stringWithFormat:@"%@ %@", cmd, uri];
    }

    // Run via /bin/sh -c (asynchronously) for %s-style command templates.
    NSArray<NSString *> *argv = @[@"/bin/sh", @"-c", expanded];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = argv[0];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    @try {
        [task launch];
    } @catch (NSException *e) {
        return NO;
    }
    return YES;
}

- (NSArray<NSString *> *)schemes {
    return self.table.allKeys;
}

@end

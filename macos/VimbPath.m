#import "VimbPath.h"

@implementation VimbPath

+ (NSString *)uniqueDestinationForPath:(NSString *)path {
    if (path.length == 0) { return path; }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) { return path; }
    NSString *base = [path stringByDeletingLastPathComponent];
    NSString *name = [path lastPathComponent];
    NSString *stem = name;
    NSString *tail = @"";   // trailing ".ext"
    NSRange tar = [name rangeOfString:@".tar."];
    if (tar.location != NSNotFound) {
        // "name.tar.gz" -> insert before ".tar."
        stem = [name substringToIndex:tar.location];
        tail = [name substringFromIndex:tar.location];
    } else {
        NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
        if (dot.location != NSNotFound && dot.location > 0) {
            stem = [name substringToIndex:dot.location];
            tail = [name substringFromIndex:dot.location];
        }
    }
    NSUInteger i = 1;
    NSString *candidate;
    do {
        candidate = [base stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"%@_%lu%@", stem, (unsigned long)i, tail]];
        i++;
    } while ([fm fileExistsAtPath:candidate]);
    return candidate;
}

@end

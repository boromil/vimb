#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure file-path helpers (Foundation only, so unit-testable in the harness).
// Mirrors the filename uniquification in src/main.c: when a destination already
// exists, an ascending `_N` suffix is inserted before the file extension so an
// existing file is never overwritten.
@interface VimbPath : NSObject

// Returns a destination that does not currently exist. If `path` already
// exists, inserts `_1`, `_2`, ... before the extension. A `.tar.` run counts
// as a two-dot extension (e.g. "a.tar.gz" -> "a_1.tar.gz"). When the base name
// has no dot, the suffix is appended ("f" -> "f_1"). Non-existent paths are
// returned unchanged.
+ (NSString *)uniqueDestinationForPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

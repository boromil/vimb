#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Simple string-list persistence mirroring vimb's file_storage (one entry per
// line). Data lives under ~/Library/Application Support/vimb.
//
// Architecture note (why this is not a dumb file wrapper): every navigation
// used to rewrite the whole history file synchronously (read-all + write-all
// on the main thread). Stores now keep the lines in memory, mutate the cache,
// and flush to disk debounced (+flushDelay). Call +flushAll at app quit (the
// app delegate does). File writes are atomic (writeToFile:atomically:YES) and
// serialized per path so two stores can never interleave partial writes to
// the same file. API is main-thread-only, like every current caller.
@interface VimbStorage : NSObject
@property(nonatomic, readonly) NSString *dir;
- (instancetype)initWithName:(NSString *)name;
// Designated: points storage at an explicit base directory (tests use a temp
// dir so real user data is never touched). The file is named by `name`.
- (instancetype)initWithName:(NSString *)name directory:(NSString *)baseDir;
// Convenience: a storage store rooted in a freshly-created temp directory.
// The `name` selects the store file inside that directory.
+ (VimbStorage *)storageInTempDirectoryWithName:(NSString *)name;
- (NSArray<NSString *> *)lines;
- (void)prepend:(NSString *)line max:(NSUInteger)max;
// Append a line to the END of the store (no dedup, no cap) — mirrors
// util_file_append (src/util.c), used by the queue `qpush` (FIFO semantics).
- (void)append:(NSString *)line;
- (void)removeLine:(NSString *)line;
- (void)writeAll:(NSArray<NSString *> *)lines;
- (void)clear;
- (nullable NSString *)popLast;   // pops front (queue / closed helpers)
- (void)push:(NSString *)line max:(NSUInteger)max;
- (nullable NSString *)top;
// Write any pending (debounced) content to disk now. Returns NO when the
// write failed (error out param). Safe to call when nothing is pending.
- (BOOL)flush:(NSError * _Nullable * _Nullable)error;
// Flushes every live store's pending content (call at application quit).
// Instances are tracked weakly, so abandoned stores are not kept alive.
+ (void)flushAll;
// Debounce interval. Tests set 0 for immediate writes; default 0.5s.
@property(nonatomic, class) NSTimeInterval flushDelay;
+ (nullable NSString *)appSupportDir;
+ (nullable NSString *)cacheDir;
@end

NS_ASSUME_NONNULL_END

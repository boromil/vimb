#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Simple string-list persistence mirroring vimb's file_storage (one entry per
// line). Data lives under ~/Library/Application Support/vimb.
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
+ (nullable NSString *)appSupportDir;
+ (nullable NSString *)cacheDir;
@end

NS_ASSUME_NONNULL_END

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
- (void)removeLine:(NSString *)line;
- (void)writeAll:(NSArray<NSString *> *)lines;
- (void)clear;
- (nullable NSString *)popLast;   // last closed / queue helpers
- (void)push:(NSString *)line max:(NSUInteger)max;
- (nullable NSString *)top;
+ (nullable NSString *)appSupportDir;
+ (nullable NSString *)cacheDir;
@end

NS_ASSUME_NONNULL_END

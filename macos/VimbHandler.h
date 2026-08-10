#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// External URI-scheme handlers, ported from src/handler.c. Maps a scheme
// (before the first ':') to a command template; the URI is substituted for
// the first '%s' (or appended) and run via the shell.
@interface VimbHandler : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *table;
- (instancetype)init;
- (BOOL)addScheme:(NSString *)scheme command:(NSString *)command;
- (BOOL)removeScheme:(NSString *)scheme;
// Look up a command template for a URI's scheme (e.g. "mailto:..." -> "mailto").
- (nullable NSString *)commandForURI:(NSString *)uri;
// Run the handler for a URI if one is registered. Returns YES if handled.
- (BOOL)handleURI:(NSString *)uri;
// All registered schemes (for completion).
- (NSArray<NSString *> *)schemes;
@end

NS_ASSUME_NONNULL_END

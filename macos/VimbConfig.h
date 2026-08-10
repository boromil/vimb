#import <Foundation/Foundation.h>
#import "VimbStorage.h"
#import "VimbAutocmd.h"

NS_ASSUME_NONNULL_BEGIN

// Application-wide configuration: settings registry (port of setting.c),
// shortcuts, and persistent storage handles. Shared across windows.
@interface VimbConfig : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *settings;   // name -> VSetting
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *shortcuts;
@property(nonatomic, copy) NSString *defaultShortcut;
@property(nonatomic, strong) VimbStorage *historyStore;
@property(nonatomic, strong) VimbStorage *commandStore;
@property(nonatomic, strong) VimbStorage *searchStore;
@property(nonatomic, strong) VimbStorage *bookmarkStore;
@property(nonatomic, strong) VimbStorage *closedStore;
@property(nonatomic, strong) VimbStorage *queueStore;
@property(nonatomic, strong) VimbAutocmd *autocmd;
@property(nonatomic, assign) NSInteger scrollstep;
@property(nonatomic, assign) NSInteger historyMax;
@property(nonatomic, assign) NSInteger closedMax;
@property(nonatomic, assign) BOOL incsearch;
@property(nonatomic, assign) BOOL smoothScrolling;
@property(nonatomic, assign) BOOL hintFollowLast;
@property(nonatomic, assign) BOOL hintKeysSameLength;
@property(nonatomic, assign) BOOL hintMatchElement;
@property(nonatomic, copy) NSString *hintKeys;
@property(nonatomic, assign) NSInteger hintTimeout;
@property(nonatomic, copy) NSString *homePage;

+ (instancetype)shared;
- (void)loadDefaults;
- (void)applySetting:(NSString *)name value:(id)value;
- (id)get:(NSString *)name;
- (BOOL)getBool:(NSString *)name defaultValue:(BOOL)dv;
- (NSInteger)getInt:(NSString *)name defaultValue:(NSInteger)dv;
- (NSString *)getString:(NSString *)name defaultValue:(NSString *)dv;

// Shortcuts (e.g. "dd" -> "https://duckduckgo.com/?q=$0")
- (nullable NSString *)resolveShortcut:(NSString *)input;
- (NSString *)historyCommand;   // config file path (rc)
- (void)sourceConfigFile;
@end

NS_ASSUME_NONNULL_END

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

// Key mapping registry (port of map.c). Keyed by mode: "n" (normal), "i"
// (insert), "c" (command line). Each mode maps to an array of entries:
//   @{ @"lhs": NSString, @"rhs": NSString, @"noremap": NSNumber(BOOL) }
// The lhs/rhs are stored in "parser form" (control chars for <C-x>, literal
// chars otherwise) so lookups by typed key match directly.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *mappings;

// Register (insert) a mapping in parser form; identical lhs for the mode is
// replaced first (mirrors map_insert). Returns the registered entry.
- (NSDictionary<NSString *, id> *)addMappingForMode:(NSString *)mode
                                                lhs:(NSString *)lhs
                                                rhs:(NSString *)rhs
                                            noremap:(BOOL)noremap;
// Remove a mapping by its parser-form lhs. Returns YES if removed.
- (BOOL)removeMappingForMode:(NSString *)mode lhs:(NSString *)lhs;
// Resolve a typed key buffer against the mode's mappings.
// Returns a dict with "status" = "ambiguous" | "match" | "none". On "match"
// it also carries "lhs"/"rhs"/"noremap". Mirrors map_handle_keys lookup.
- (NSDictionary<NSString *, id> *)resolveMappingForMode:(NSString *)mode buffer:(NSString *)buffer;
// Convert a config-file key string ("X", "<C-x>", "<Esc>", ...) into parser
// form (the same character form the key handler feeds the normal parser).
- (NSString *)convertKeyString:(NSString *)str;

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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Builds the main menu bar per HIG: a full NSMenu with key equivalents so
// every toolbar action is also reachable and discoverable from the menu bar.
@interface VimbMenu : NSObject
+ (NSMenu *)mainMenu;
@end

NS_ASSUME_NONNULL_END

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Window subclass that guarantees the browser navigation key equivalents
// (Cmd-T new tab, Cmd-W close tab) are handled regardless of the current
// first responder or whether AppKit's menu key-equivalent dispatch happens to
// reach them. Falling back to super (the menu) when not handled.
@interface VimbWindow : NSWindow
@end

NS_ASSUME_NONNULL_END

#import <Cocoa/Cocoa.h>
#import "VimController.h"

@class KeyboardWebView;

NS_ASSUME_NONNULL_BEGIN

// Tells the app owner to drop a window controller from its list when closed.
typedef void (^WindowReleasedHandler)(NSWindowController *wc);

@interface BrowserWindowController : NSWindowController <NSWindowDelegate>
@property(nonatomic, copy, nullable) WindowReleasedHandler windowReleasedHandler;

- (void)loadURL:(NSString *)urlValue;
- (void)loadURL:(NSString *)urlValue inNewTab:(BOOL)newTab;

// Vim actions
- (void)openNewTab;
- (void)closeActiveTab;
- (void)nextTab;
- (void)prevTab;
- (void)selectTabAtIndex:(NSUInteger)index;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)commandLineExecuted:(NSString *)line;
- (void)showMessage:(NSString *)message error:(BOOL)error;
@end

NS_ASSUME_NONNULL_END

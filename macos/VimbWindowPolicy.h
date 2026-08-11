#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Where to route a popup / target=_blank / window.open request, mirroring
// vimb's on_webview_create (src/main.c) and decide_new_window_action. The
// WKUIDelegate plumbing lives in KeyboardWebView; this class holds the
// decision so it is unit-testable (Foundation-only, no AppKit).
typedef NS_ENUM(NSInteger, VimbWindowTarget) {
    VimbWindowTargetCurrent,  // load the URL into the current tab (prevent-newwindow ON)
    VimbWindowTargetNewTab,   // open the URL in a new tab (prevent-newwindow OFF)
    VimbWindowTargetBlock,    // drop the request entirely
};

@interface VimbWindowPolicy : NSObject

// Maps a WKNavigationType + user-gesture flag to a routing decision, honoring
// the prevent-newwindow setting. Mirrors decide_new_window_action: gesture-gated
// new-window requests route to Current when prevent-newwindow is set, otherwise
// to a new tab; gesture-less JS-driven (navigationType == Other) window.open
// requests are dropped unless prevent-newwindow is on (where the URL is still
// useful) — see KeyboardWebView for the exact navigation-type classification.
+ (VimbWindowTarget)targetForNavigationType:(NSInteger)navigationType
                                userGesture:(BOOL)userGesture
                           preventNewWindow:(BOOL)preventNewWindow;

@end

NS_ASSUME_NONNULL_END

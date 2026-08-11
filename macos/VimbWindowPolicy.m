#import "VimbWindowPolicy.h"

// WKNavigationType values (WebKit). Defined here so this Foundation-only class
// needs no WebKit import.
static const NSInteger VWPNavLinkActivated = 0;
static const NSInteger VWPNavFormSubmitted = 1;
static const NSInteger VWPNavBackForward  = 2;
static const NSInteger VWPNavReload       = 4;

@implementation VimbWindowPolicy

+ (VimbWindowTarget)targetForNavigationType:(NSInteger)navigationType
                                userGesture:(BOOL)userGesture
                           preventNewWindow:(BOOL)preventNewWindow {
    // prevent-newwindow ON: pull any popup request into the current tab
    // (parity with on_webview_create in src/main.c). This is honored for all
    // navigation types — the popup URL is still captured and shown.
    if (preventNewWindow) {
        return VimbWindowTargetCurrent;
    }

    // prevent-newwindow OFF. Mirror decide_new_window_action (src/main.c):
    // gesture-driven new-window requests open in a new tab. Gesture-less JS
    // window.open (navigationType == Other) is dropped here; WKWebView itself
    // enforces javaScriptCanOpenWindowsAutomatically for non-gesture popups.
    switch (navigationType) {
        case VWPNavLinkActivated:
        case VWPNavFormSubmitted:
        case VWPNavBackForward:
        case VWPNavReload:
            return userGesture ? VimbWindowTargetNewTab : VimbWindowTargetBlock;
        default: // WKNavigationTypeOther and any unrecognised value
            return VimbWindowTargetBlock;
    }
}

@end

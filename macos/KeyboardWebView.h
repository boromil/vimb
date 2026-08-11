#import <WebKit/WebKit.h>
#import "VimController.h"

NS_ASSUME_NONNULL_BEGIN

@class KeyboardWebView;

@protocol KeyboardWebViewDelegate <NSObject>
- (VimController *)vimControllerForView:(KeyboardWebView *)view;
@optional
- (void)webView:(KeyboardWebView *)view didUpdateTitle:(nullable NSString *)title;
- (void)webView:(KeyboardWebView *)view didUpdateProgress:(double)progress;
- (void)webView:(KeyboardWebView *)view didFinishLoadWithURL:(nullable NSURL *)url;
- (void)webView:(KeyboardWebView *)view didReceiveMessage:(NSDictionary *)payload;
// Route a popup / target=_blank / window.open URL (parity with
// on_webview_create + decide_new_window_action). newTab: YES routes to a new
// tab, NO loads it in the current tab.
- (void)webView:(KeyboardWebView *)view openTargetURL:(nullable NSString *)url newTab:(BOOL)newTab;
@end

@interface KeyboardWebView : WKWebView <WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate, WKUIDelegate>
@property(nonatomic, weak, nullable) id<KeyboardWebViewDelegate> vbDelegate;
@property(nonatomic, readonly) BOOL canGoDeeperForward;
- (instancetype)initWithFrame:(NSRect)frame;
// call the hint-toggle JS
- (void)toggleHints;
- (void)toggleHints:(nullable NSString *)followMode;   // followMode: a full hint mode char ("o","t","y","i","e","k","s","x","p",...)
- (void)toggleHints:(nullable NSString *)followMode gmode:(BOOL)gmode;   // g-mode (keep-open) hinting
- (void)sendHintKey:(NSString *)key;
- (void)sendHintKey:(nullable NSString *)key mode:(nullable NSString *)followMode;
// Hint-mode editing controls (Esc/Enter/Tab/Backspace) forwarded to the JS.
- (void)hintClear;
- (void)hintFocus:(BOOL)back;
- (void)hintBackspace;
- (void)hintFire;
- (void)findString:(NSString *)query forwardDirection:(BOOL)forward;
- (void)executeCommand:(NSString *)line;
- (void)scrollToTop;
- (void)scrollToBottom;
- (void)scrollToPercent:(NSUInteger)percent;
- (void)scrollToMiddle;
- (void)scrollToX:(double)x;
- (void)scrollToXEnd;
- (void)scrollBy:(double)dx y:(double)dy;
- (void)findNextDirection:(BOOL)forward;
- (void)focusLastActiveElement;
- (void)focusFirstInput;
- (void)incrementURI:(NSInteger)delta;
- (void)getScrollTopWithCompletion:(void (^)(double top))completion;
- (void)scrollToY:(double)y;
- (void)jumpToURI:(NSString *)uri withY:(double)y;
@end

NS_ASSUME_NONNULL_END

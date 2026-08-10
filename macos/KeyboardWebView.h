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
@end

@interface KeyboardWebView : WKWebView <WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate>
@property(nonatomic, weak, nullable) id<KeyboardWebViewDelegate> vbDelegate;
@property(nonatomic, readonly) BOOL canGoDeeperForward;
- (instancetype)initWithFrame:(NSRect)frame;
// call the hint-toggle JS
- (void)toggleHints;
- (void)toggleHints:(nullable NSString *)followMode;   // followMode: "f","t","o","y","i"...
- (void)sendHintKey:(NSString *)key;
- (void)sendHintKey:(nullable NSString *)key mode:(nullable NSString *)followMode;
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
- (void)getScrollTopWithCompletion:(void (^)(double top))completion;
- (void)scrollToY:(double)y;
- (void)jumpToURI:(NSString *)uri withY:(double)y;
@end

NS_ASSUME_NONNULL_END

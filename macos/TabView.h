#import <Cocoa/Cocoa.h>

@class KeyboardWebView;

NS_ASSUME_NONNULL_BEGIN

// A single browser tab: owns its KeyboardWebView and tab metadata.
@interface VimbTab : NSObject
@property(nonatomic, strong) KeyboardWebView *webView;
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, copy, nullable) NSURL *url;
@property(nonatomic, readonly) NSView *view;
- (instancetype)initWithWebView:(KeyboardWebView *)webView;
@end

NS_ASSUME_NONNULL_END

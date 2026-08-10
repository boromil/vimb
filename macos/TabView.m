#import "TabView.h"
#import "KeyboardWebView.h"

@implementation VimbTab

- (instancetype)initWithWebView:(KeyboardWebView *)webView {
    self = [super init];
    if (self) {
        _webView = webView;
        _title = @"New Tab";
    }
    return self;
}

- (NSView *)view {
    return self.webView;
}

@end

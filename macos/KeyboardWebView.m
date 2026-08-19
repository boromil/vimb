#import "KeyboardWebView.h"
#import "VimbConfig.h"
#import "VimbAutocmd.h"
#import "VimbPermissionPolicy.h"
#import "VimbContextMenu.h"
#import "VimbEx.h"
#import "VimbWindowPolicy.h"
#import "VimbTaskRunner.h"
#import "VimbScripts.h"

// Page JS lives in scripts/*.js and is embedded by scripts/mkjsheader.sh
// (parity with src/scripts/js2h.sh). Edit the .js files, not this file.

// This view is created programmatically only (no nibs/coders), so the
// designated-initializer consistency warnings don't apply.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// A tiny embedded JS helper injected as a user script (from scripts/vimbcore.js).
// It provides scroll primitives and a message bus bridged back to native via
// window.webkit. See scripts/vimbcore.js for the source.

@implementation KeyboardWebView {
    NSString *_lastQuery;
    BOOL _editableFocusActive;
    double _pendingMarkY;
    double _autofocusCooldownUntil; // ignore scripted autofocus briefly post-load
    // URL of the link under the last right-click, resolved via JS before the
    // WK context menu is rebuilt (see willOpenMenu:withEvent:).
    NSString *_contextLinkURL;
}

// Builds a user script that injects a <style> element carrying the vimb
// completion CSS settings as page CSS classes. Settings default to empty, so
// the script is a harmless no-op unless overridden via :set. Escaped so the
// CSS text cannot break out of the <style> element.
- (NSString *)completionCSSScript {
    VimbConfig *cfg = [VimbConfig shared];
    NSDictionary *rules = @{
        @".vimb-completion":            [cfg getString:@"completion-css"         defaultValue:@""],
        @".vimb-completion-hover":      [cfg getString:@"completion-hover-css"   defaultValue:@""],
        @".vimb-completion-selected":   [cfg getString:@"completion-selected-css" defaultValue:@""],
    };
    NSMutableString *css = [NSMutableString string];
    [rules enumerateKeysAndObjectsUsingBlock:^(NSString *sel, NSString *style, BOOL *stop) {
        (void)stop;
        if (style.length == 0) { return; }
        // Strip </style> / <style sequences to keep the injection well-formed.
        NSString *s = style;
        s = [s stringByReplacingOccurrencesOfString:@"</" withString:@"<\\/"];
        [css appendFormat:@"%@{%@}\n", sel, s];
    }];
    if (css.length == 0) { return @""; }
    // Return a valid (no-op when empty) user script source.
    NSString *src = [NSString stringWithFormat:
        @"(function(){var s=document.createElement('style');"
         "s.type='text/css';s.appendChild(document.createTextNode(%@));"
         "if(document.head){document.head.appendChild(s);}else{document.addEventListener('DOMContentLoaded',"
         "function(){if(document.head)document.head.appendChild(s);});}})();",
        [self jsStringLiteral:css]];
    return src;
}

// JSON-encodes a string so it can be embedded as a JS string literal.
- (NSString *)jsStringLiteral:(NSString *)str {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:str options:0 error:&err];
    if (err || !data) { return @"\"\""; }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (instancetype)initWithFrame:(NSRect)frame {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.preferences = [[WKPreferences alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // Apply the webkit-settable settings from vimb's setting registry.
    VimbConfig *cfg = [VimbConfig shared];
    WKPreferences *prefs = config.preferences;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    prefs.javaScriptEnabled = [cfg getBool:@"scripts" defaultValue:YES];
#pragma clang diagnostic pop
    prefs.javaScriptCanOpenWindowsAutomatically = [cfg getBool:@"javascript-can-open-windows-automatically" defaultValue:NO];
    if ([cfg getBool:@"webinspector" defaultValue:NO]) {
        [prefs setValue:@YES forKey:@"developerExtrasEnabled"];
    }
    [prefs setValue:@([cfg getInt:@"font-size" defaultValue:16]) forKey:@"defaultFontSize"];
    prefs.minimumFontSize = (CGFloat)[cfg getInt:@"minimum-font-size" defaultValue:5];

    // Note: no KVC setValue: on WKPreferences for private keys here — setting
    // mediaPlaybackRequiresUserGesture/mediaPlaybackAllowsInline via KVC during
    // configuration blocked WKWebView init (seen as an app launch hang). Only
    // the public preferences above are applied.
    config.defaultWebpagePreferences.allowsContentJavaScript =
        [cfg getBool:@"scripts" defaultValue:YES];

    // Config-time WKWebViewConfiguration settings (parity with webkit settings
    // in setting.c). These are public config properties — NOT KVC on WKPreferences
    // — so they avoid the mediaPlayback* init hang noted below. They must be set
    // before the web view is created.
    // print-backgrounds (default on) -> WKPreferences.shouldPrintBackgrounds.
    prefs.shouldPrintBackgrounds = [cfg getBool:@"print-backgrounds" defaultValue:YES];
    // media-playback-requires-user-gesture (default off) -> WKAudiovisualMediaTypes
    // (macOS 10.12+): off means no user action required for any media; on means
    // all media require it. Note: media-playback-allows-inline has no macOS WK
    // counterpart (it is iOS-only) — on desktop playback is inline by default,
    // so that setting is a no-op here and stays registered but unused.
    BOOL requireGesture = [cfg getBool:@"media-playback-requires-user-gesture" defaultValue:NO];
    config.mediaTypesRequiringUserActionForPlayback =
        requireGesture ? WKAudiovisualMediaTypeAll : WKAudiovisualMediaTypeNone;

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:kVimbScriptVimbcore
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                              forMainFrameOnly:NO];
    [ucc addUserScript:script];

    // Port of vimb's completion-* CSS settings. The native completion dropdown
    // isn't a page element, so instead of applying inline styles we expose the
    // settings as CSS classes on the page for any consumer (a future native
    // dropdown, or a site that opts in) to build on. Non-breaking: empty CSS
    // settings produce a no-op stylesheet.
    WKUserScript *cssScript = [[WKUserScript alloc] initWithSource:[self completionCSSScript]
                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                 forMainFrameOnly:NO];
    [ucc addUserScript:cssScript];

    // User scripts.js / style.css from the config dir (parity with
    // user_scripts/user_style in setting.c): inject at document end.
    NSString *userScript = [[VimbConfig shared] userScriptSource];
    if (userScript) {
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:userScript
                                                   injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                forMainFrameOnly:NO]];
    }
    NSString *userStyle = [[VimbConfig shared] userStyleSource];
    if (userStyle) {
        // Inject the user stylesheet as a <style> element (WKUserStyleSheet is a
        // private API on this SDK). Parity with user_style in setting.c.
        NSString *escapedCSS = [userStyle stringByReplacingOccurrencesOfString:@"</" withString:@"<\\/"];
        NSString *styleJS = [NSString stringWithFormat:
            @"(function(){if(document.getElementById('vimb-user-style'))return;"
            @"var s=document.createElement('style');s.id='vimb-user-style';"
            @"s.textContent=%@;"
            @"(document.head||document.documentElement).appendChild(s);})();",
            [self jsStringLiteral:escapedCSS]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:styleJS
                                                   injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                forMainFrameOnly:NO]];
    }

    [ucc addScriptMessageHandler:self name:@"vimb"];
    config.userContentController = ucc;

    self = [super initWithFrame:frame configuration:config];
    if (self) {
        self.navigationDelegate = self;
        self.UIDelegate = self;
        self.allowsBackForwardNavigationGestures = YES;
        // Honor the user-agent setting (parity with webkit settings in setting.c,
        // whose user-agent maps to webkit_settings_set_user_agent). An explicit
        // customUserAgent replaces the entire WKWebView default UA string.
        NSString *ua = [[VimbConfig shared] getString:@"user-agent" defaultValue:@""];
        if (ua.length) { self.customUserAgent = ua; }
        [self addObserver:self forKeyPath:@"estimatedProgress" options:0 context:NULL];
        [self addObserver:self forKeyPath:@"title" options:0 context:NULL];
        [self addObserver:self forKeyPath:@"URL" options:0 context:NULL];

        // cookie-accept (parity with cookie_accept in src/setting.c). WKWebView
        // exposes only Allow/Disallow (macOS 14+); the "origin" (no-third-party)
        // mode has no public WKWebView equivalent, so it degrades to Allow.
        // This setting needs the (default) data store, so apply it once here.
        NSString *accept = [[VimbConfig shared] getString:@"cookie-accept" defaultValue:@"always"];
        if (@available(macOS 14.0, *)) {
            WKCookiePolicy cookiePolicy = WKCookiePolicyAllow;
            if ([accept isEqualToString:@"never"]) { cookiePolicy = WKCookiePolicyDisallow; }
            [config.websiteDataStore.httpCookieStore setCookiePolicy:cookiePolicy
                                                   completionHandler:nil];
        }
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration {
    return [self initWithFrame:frame];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSZeroRect];
}

- (void)dealloc {
    [self.configuration.userContentController removeScriptMessageHandlerForName:@"vimb"];
    @try {
        [self removeObserver:self forKeyPath:@"estimatedProgress"];
        [self removeObserver:self forKeyPath:@"title"];
        [self removeObserver:self forKeyPath:@"URL"];
    } @catch (NSException *e) {}
}

#pragma mark - Key handling

- (void)keyDown:(NSEvent *)event {
    VimController *vim = [self.vbDelegate vimControllerForView:self];
    if (vim && [vim shouldPassKeysToPage:_editableFocusActive]) {
        // A text input is focused. Handle input-mode keys (Ctrl-O one-shot
        // normal, ESC blur) first; otherwise let typing reach the page.
        NSString *cs = event.charactersIgnoringModifiers;
        unichar c = cs.length ? [cs characterAtIndex:0] : 0;
        if (c == 27) {
            [self evaluateJavaScript:@"document.activeElement&&document.activeElement.blur?document.activeElement.blur():0;"
                      completionHandler:nil];
            _editableFocusActive = NO;
            return;
        }
        int keyCode = (int)c;
        // Ctrl-O one-shot: intercept when Ctrl held.
        if ((event.modifierFlags & NSEventModifierFlagControl) != 0) {
            if ([vim handlePageEditableKeyCode:keyCode
                                     modifiers:(unsigned long)event.modifierFlags
                                    characters:cs]) {
                return;
            }
        } else if (vim.oneShotNormal) {
            if ([vim handlePageEditableKeyCode:keyCode
                                     modifiers:0
                                    characters:cs]) {
                return;
            }
        }
        [super keyDown:event];
        return;
    }
    if (vim && [vim handleKeyDown:event inWebView:YES]) {
        return; // consumed by vim
    }
    [super keyDown:event];
}

- (void)keyUp:(NSEvent *)event {
    [super keyUp:event];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Cmd key combos are handled by the app menu / default bindings. Let them
    // propagate; only intercept when a vim mode explicitly needs them.
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        return [super performKeyEquivalent:event];
    }
    return [super performKeyEquivalent:event];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        id<KeyboardWebViewDelegate> d = self.vbDelegate;
        if (d && [d respondsToSelector:@selector(webView:didUpdateProgress:)]) {
            [d webView:self didUpdateProgress:self.estimatedProgress];
        }
    } else if ([keyPath isEqualToString:@"title"]) {
        id<KeyboardWebViewDelegate> d = self.vbDelegate;
        if (d && [d respondsToSelector:@selector(webView:didUpdateTitle:)]) {
            [d webView:self didUpdateTitle:self.title];
        }
    }
}

#pragma mark - Navigation

// Hand off URLs for schemes with a registered external handler (e.g.
// "mailto:", "tel:") instead of trying to load them, matching handler.c.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    // Cmd-click / middle-click on a link opens it in a new tab (Safari-style;
    // GTK parity: main.c maps CTRL-LeftMouse / MiddleMouse to a new instance,
    // which is a new tab in this port's single-window model). WKWebView does
    // NOT route modifier-clicks through createWebViewWithConfiguration, so
    // intercept them here: a LinkActivated navigation carrying the Command
    // modifier is exactly that gesture.
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        NSEventModifierFlags mod = navigationAction.modifierFlags;
        BOOL cmdClick = (mod & NSEventModifierFlagCommand) != 0;
        // Middle-click arrives as a plain LinkActivated without modifiers
        // (the button press itself never becomes a key-modified navigation);
        // WK offers no public button info, so cmd-click is the supported path.
        if (cmdClick) {
            id<KeyboardWebViewDelegate> d = self.vbDelegate;
            if (url.absoluteString.length
                && [d respondsToSelector:@selector(webView:openTargetURL:newTab:)]) {
                decisionHandler(WKNavigationActionPolicyCancel);
                [d webView:self openTargetURL:url.absoluteString newTab:YES];
                return;
            }
        }
    }
    static NSSet<NSString *> *internal = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        internal = [NSSet setWithArray:@[@"http", @"https", @"file", @"about", @"data",
                                          @"javascript", @"ws", @"wss", @"blob"]];
    });
    if (scheme && ![internal containsObject:scheme]
        && [[VimbConfig shared].handler handleURI:url.absoluteString]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

// TLS policy (parity with tls_policy / strict-ssl in setting.c): when
// strict-ssl is OFF, accept server-trust challenges; when ON, reject them.
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    BOOL strict = [[VimbConfig shared] getBool:@"strict-ssl" defaultValue:YES];
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (!strict && space.authenticationMethod == NSURLAuthenticationMethodServerTrust) {
        // Accept the (untrusted) server certificate.
        NSURLCredential *cred = [NSURLCredential credentialForTrust:space.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)nav {
    NSString *uri = self.URL.absoluteString ?: @"";
    [[VimbConfig shared].autocmd fireEvent:VAuLoadStarting uri:uri];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)nav {
    NSString *uri = self.URL.absoluteString ?: @"";
    [[VimbConfig shared].autocmd fireEvent:VAuLoadCommitted uri:uri];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)nav {
    if (_pendingMarkY != 0) {
        [self scrollToY:_pendingMarkY];
        _pendingMarkY = 0;
    }
    // Start each page in vim normal mode (mirrors vimb vb_enter('n') on load):
    // drop any page-editable focus so keys route to the vim engine even if the
    // page autofocused a search/input field.
    _editableFocusActive = NO;
    // Suppress a (possibly delayed) scripted autofocus for a short window after
    // load so vim keys like ":" and "o" work immediately on the start page; the
    // user can still click into a field to type.
    _autofocusCooldownUntil = [[NSDate date] timeIntervalSinceReferenceDate] + 0.75;
    [self evaluateJavaScript:@"(()=>{const e=document.activeElement;if(e&&(e.isContentEditable||/^(INPUT|TEXTAREA)$/.test(e.tagName)))e.blur();})()"
            completionHandler:nil];
    // Apply the default-zoom setting (parity with default_zoom in setting.c).
    CGFloat zoom = [[VimbConfig shared] getInt:@"default-zoom" defaultValue:100] / 100.0;
    if (zoom > 0 && zoom != 1.0 && self.magnification != zoom) {
        self.magnification = zoom;
    }
    NSString *uri = self.URL.absoluteString ?: @"";
    [[VimbConfig shared].autocmd fireEvent:VAuLoadFinished uri:uri];
    id<KeyboardWebViewDelegate> d = self.vbDelegate;
    if (d && [d respondsToSelector:@selector(webView:didFinishLoadWithURL:)]) {
        [d webView:self didFinishLoadWithURL:self.URL];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)nav withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) {
        id<KeyboardWebViewDelegate> d = self.vbDelegate;
        if (d && [d respondsToSelector:@selector(webView:didReceiveMessage:)]) {
            [d webView:self didReceiveMessage:@{@"t": @"loaderror", @"s": error.localizedDescription ?: @""}];
        }
    }
}

#pragma mark - Popup / new-window policy (parity with src/main.c)

// Handle window.open and target=_blank popups. We never host a child WKWebView;
// instead we route the requested URL to a new tab (prevent-newwindow OFF) or the
// current tab (prevent-newwindow ON), matching on_webview_create + decide_new_window_action.
- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSInteger type = (NSInteger)navigationAction.navigationType;
    // WKNavigationAction exposes no public user-gesture flag; a real popup
    // (link/form) reaches us as LinkActivated/FormSubmitted, and WK only calls
    // this delegate when it would allow the popup, so that is treated as a
    // user gesture. Gesture-less JS window.open is gated natively by
    // javaScriptCanOpenWindowsAutomatically (implemented in this config).
    BOOL userGesture = (type == WKNavigationTypeLinkActivated
                        || type == WKNavigationTypeFormSubmitted
                        || type == WKNavigationTypeBackForward
                        || type == WKNavigationTypeReload);
    VimbWindowTarget target = [VimbWindowPolicy targetForNavigationType:type
                                                            userGesture:userGesture
                                                       preventNewWindow:[[VimbConfig shared] getBool:@"prevent-newwindow" defaultValue:NO]];
    if (target == VimbWindowTargetBlock) {
        return nil;
    }
    NSString *url = navigationAction.request.URL.absoluteString;
    id<KeyboardWebViewDelegate> delegate = self.vbDelegate;
    if (url.length && [delegate respondsToSelector:@selector(webView:openTargetURL:newTab:)]) {
        [delegate webView:self
            openTargetURL:url
                   newTab:(target == VimbWindowTargetNewTab)];
    }
    return nil;
}

#pragma mark - Permissions (parity with on_permission_request in main.c)

// Present a keyboard-operable Allow/Deny alert for a page permission request and
// forward the choice as a WKPermissionDecision.
- (void)promptPermissionMessage:(NSString *)message
                decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Allow this page to continue?";
    alert.informativeText = [NSString stringWithFormat:@"Page wants to %@.", message];
    [alert addButtonWithTitle:@"Allow"];
    [alert addButtonWithTitle:@"Deny"];
    alert.alertStyle = NSAlertStyleInformational;
    NSWindow *host = self.window;
    if (host) {
        [alert beginSheetModalForWindow:host completionHandler:^(NSModalResponse response) {
            decisionHandler(response == NSAlertFirstButtonReturn
                            ? WKPermissionDecisionGrant
                            : WKPermissionDecisionDeny);
        }];
    } else {
        // No window yet: deny so the request is never left hanging.
        decisionHandler(WKPermissionDecisionDeny);
    }
}

// Gate: with media-stream off, the page cannot access camera/microphone at all
// (mirrors webkit default; setting.c maps media-stream to enable-media-stream).
- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
 initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
 decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    VimbConfig *cfg = [VimbConfig shared];
    VimbPermissionDecision decision =
        [VimbPermissionPolicy mediaCaptureDecisionForEnabled:[cfg getBool:@"media-stream" defaultValue:NO]];
    if (decision == VimbPermissionDeny) {
        decisionHandler(WKPermissionDecisionDeny);
        return;
    }
    VimbCaptureKind kind;
    switch (type) {
        case WKMediaCaptureTypeMicrophone:   kind = VimbCaptureMicrophone; break;
        case WKMediaCaptureTypeCamera:       kind = VimbCaptureCamera; break;
        case WKMediaCaptureTypeCameraAndMicrophone:
        default:                             kind = VimbCaptureCameraAndMicrophone; break;
    }
    [self promptPermissionMessage:[VimbPermissionPolicy mediaCapturePromptForKind:kind]
                  decisionHandler:decisionHandler];
}

// geolocation setting: ask / always / never (parity with setting.c geolocation()).
- (void)webView:(WKWebView *)webView requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
 initiatedByFrame:(WKFrameInfo *)frame
 decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    VimbConfig *cfg = [VimbConfig shared];
    VimbPermissionDecision decision =
        [VimbPermissionPolicy geolocationDecisionForOption:
            [cfg getString:@"geolocation" defaultValue:@"ask"]];
    if (decision == VimbPermissionGrant) {
        decisionHandler(WKPermissionDecisionGrant);
        return;
    }
    if (decision == VimbPermissionDeny) {
        decisionHandler(WKPermissionDecisionDeny);
        return;
    }
    // ask
    [self promptPermissionMessage:@"access your location"
                  decisionHandler:decisionHandler];
}

#pragma mark - Script messages (JS -> native)

- (void)userContentController:(WKUserContentController *)uc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"vimb"]) { return; }
    if ([message.body isKindOfClass:[NSDictionary class]]) {
        NSDictionary *body = (NSDictionary *)message.body;
        // Track text-input focus so keys pass through to the page.
        if ([body[@"t"] isEqualToString:@"focusactive"]) {
            // Ignore programmatic autofocus right after a page load so vim
            // keys work immediately; a real click after the cooldown re-enables
            // page typing.
            if ([[NSDate date] timeIntervalSinceReferenceDate] >= _autofocusCooldownUntil) {
                _editableFocusActive = YES;
            }
        }
        if ([body[@"t"] isEqualToString:@"focusclear"]) {
            _editableFocusActive = NO;
        }
        id<KeyboardWebViewDelegate> d = self.vbDelegate;
        if (d && [d respondsToSelector:@selector(webView:didReceiveMessage:)]) {
            [d webView:self didReceiveMessage:body];
        }
    }
}

#pragma mark - Downloads

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)action
    didBecomeDownload:(WKDownload *)download {
    [self adoptDownload:download];
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)response
    didBecomeDownload:(WKDownload *)download {
    [self adoptDownload:download];
}

- (void)adoptDownload:(WKDownload *)download {
    // download-use-external: run download-command with the URL and do not save
    // locally (parity with spawn_download_command in src/main.c). The URI is
    // shell-quoted by VimbTaskRunner so remote content can never inject shell
    // metacharacters; VIMB_URI/VIMB_DOWNLOAD_PATH are exported like GTK.
    VimbConfig *cfg = [VimbConfig shared];
    NSString *uri = self.URL.absoluteString ?: @"";
    if ([cfg getBool:@"download-use-external" defaultValue:NO] && uri.length) {
        NSString *cmd = [cfg getString:@"download-command" defaultValue:@"/usr/bin/open %s"];
        NSString *expanded = [VimbTaskRunner expandTemplate:cmd value:uri];
        NSDictionary<NSString *, NSString *> *env = @{
            @"VIMB_URI": uri,
            @"VIMB_DOWNLOAD_PATH": [cfg getString:@"download-path" defaultValue:@"~/Downloads"],
        };
        [VimbTaskRunner runAsync:expanded environment:env error:nil];
        // The external command owns the URL; WKDownload may still fetch it but
        // we don't adopt the delegate so no file is saved under download-path.
        return;
    }
    download.delegate = self;
    [[VimbConfig shared].autocmd fireEvent:VAuDownloadStarted uri:uri];
}

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
  suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL *destination))completionHandler {
    // Honor the download-path setting (parity with vb_download_set_destination).
    NSString *destDir = [[VimbConfig shared] downloadsDirectory];
    NSURL *dir = [NSURL fileURLWithPath:destDir isDirectory:YES];
    NSURL *dest = [dir URLByAppendingPathComponent:suggestedFilename ?: @"download"];
    completionHandler(dest);
}

- (void)downloadDidFinish:(WKDownload *)download {
    [[VimbConfig shared].autocmd fireEvent:VAuDownloadFinished uri:self.URL.absoluteString];
    id<KeyboardWebViewDelegate> d = self.vbDelegate;
    if (d && [d respondsToSelector:@selector(webView:didReceiveMessage:)]) {
        [d webView:self didReceiveMessage:@{@"t": @"download-done"}];
    }
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    [[VimbConfig shared].autocmd fireEvent:VAuDownloadFailed uri:self.URL.absoluteString];
}

#pragma mark - Actions

#pragma mark - Context menu (parity with src/context-menu.c)

// The WKWebView macOS web engine builds its default right-click menu internally;
// there is no public macOS delegate hook for the WK context menu (the
// UIContextMenu-based delegate methods in WKUIDelegate.h are marked iOS-only).
// The reliable, documented way to customize it is to subclass WKWebView (we
// already are KeyboardWebView) and override -willOpenMenu:withEvent: — the same
// hook iTerm2 / iCab / the modern Safari-style engines use. After super builds
// the default items we rewire the "open … in new window" family to open in tabs
// (mirroring fix_open_in_new_window_stock_action) and append the vimb browser
// actions (Home / Hint Links / View Source / Add Bookmark / Copy URL).
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    // Let WKWebView build its default menu first (Back/Forward/Reload/Copy/
    // Open Link/…). Those already route through the same selectors the main
    // menu bar uses, so keep them; only the new-window items are replaced.
    [super willOpenMenu:menu withEvent:event];

    // Link detection: WK's default items on this macOS carry NO URL payload
    // (representedObject is nil even for "Open Link"/"Copy Link"), so the
    // URL under the click is resolved from the DOM instead. elementFromPoint
    // walks up to the enclosing <a> and returns its absolute href; the
    // right-click point in view coordinates is derived from the event.
    // WKWebView's menu event arrives with locationInWindow already in this
    // view's coordinate space (the event is delivered through the web view's
    // own event pipeline), so converting again against the window would
    // double-subtract the content insets and shift the point ~55pt low.
    NSPoint loc = event.locationInWindow;
    if (!NSPointInRect(loc, self.bounds)) {
        loc = [self convertPoint:event.locationInWindow fromView:nil];
    }
    // DOM coordinates are top-left origin; AppKit view coordinates are
    // bottom-left origin. Flip y and clamp inside the visible bounds so
    // elementFromPoint can never be handed a point outside the viewport.
    CGFloat domY = self.bounds.size.height - loc.y;
    // WK's own hit-testing (which decides the default menu items) is more
    // generous than elementFromPoint: an inline <a>'s clickable area includes
    // its line box, while elementFromPoint can return a sibling/tight box for
    // the exact same pixel. Probe a small cross pattern so a click that WK
    // treats as "on the link" resolves to the link here too.
    NSString *js = [NSString stringWithFormat:
        @"(function(){var pts=[[0,0],[6,0],[-6,0],[0,6],[0,-6],[8,0],[-8,0],[0,8],[0,-8],[0,12],[0,-12],[0,16],[0,-16],[0,20],[0,-20]];"
         @"for(var i=0;i<pts.length;i++){var e=document.elementFromPoint(%f+pts[i][0],%f+pts[i][1]);"
         @"var n=e;while(n&&n.nodeName!=='A'){n=n.parentElement;}"
         @"if(n&&n.href)return n.href;}"
         @"return null;})()", loc.x, domY];
    __block NSString *resolved = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self evaluateJavaScript:js completionHandler:^(id result, NSError *jsErr) { (void)jsErr;
        if ([result isKindOfClass:[NSString class]]) { resolved = result; }
        dispatch_semaphore_signal(sem);
    }];
    // evaluateJavaScript reports back on the main thread; since this whole
    // method already runs on the main thread, spin the run loop in default
    // mode so the JS result (and menu tracking) stay live while waiting.
    // Bounded to 0.75s so a stalled page can never wedge the menu open-less.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.75];
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        if ([[NSDate date] compare:deadline] != NSOrderedAscending) { break; }
        if (![[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                   beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]) {
            break;
        }
    }
    _contextLinkURL = resolved;
    NSString *linkURL = resolved ?: [self linkURLFromDefaultItems:menu.itemArray];

    NSArray<NSDictionary *> *tree = [VimbContextMenu menuTreeForContext:@{
        @"link": linkURL ?: @"",   // empty string means "not over a link"
        @"back": @(self.canGoBack),
        @"forward": @(self.canGoForward),
    }];

    // Keep every default item except:
    // - the "open … in new window" family, which becomes an "open in new tab"
    //   item (parity with fix_open_in_new_window_*), and
    // - WK's "Inspect Element", which on current macOS (26/27) opens a
    //   WebInspector frontend in a TUINSWindow that never gets ordered on
    //   screen (verified on a minimal WKWebView app too — the 500x500 window
    //   exists, claims onscreen after makeKeyAndOrderFront, yet paints
    //   nothing). Replace it with vimb's own DOM inspector (the gF tab) so
    //   the menu item does something visible.
    NSMutableArray *replacement = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) {
        if ([VimbContextMenu isOpenInNewWindowIdentifier:item.identifier]) {
            [replacement addObject:[self openInNewTabItemWithURLString:linkURL]];
        } else if ([item.identifier isEqualToString:@"WKMenuItemIdentifierInspectElement"]) {
            [replacement addObject:[self domInspectorItem]];
        } else {
            [replacement addObject:item];
        }
    }

    // Append the vimb browser actions, skipping any that the engine already
    // provides (Back/Forward/Reload/Copy, which map to the menu-bar selectors).
    [replacement addObjectsFromArray:[self vimbActionItemsFromTree:tree linkURL:linkURL]];

    [menu removeAllItems];
    for (NSMenuItem *item in replacement) { [menu addItem:item]; }
}

// Recovers the link URL from the WK default menu items. On current macOS the
// items carry no representedObject payload, so this is only a fallback; the
// primary path is the DOM resolution in willOpenMenu. nil means no link.
- (nullable NSString *)linkURLFromDefaultItems:(NSArray<NSMenuItem *> *)items {
    for (NSMenuItem *item in items) {
        id rep = item.representedObject;
        NSString *candidate = nil;
        if ([rep isKindOfClass:[NSURL class]]) {
            candidate = [(NSURL *)rep absoluteString];
        } else if ([rep isKindOfClass:[NSString class]] && [(NSString *)rep length]) {
            candidate = rep;
        }
        if (candidate.length) { return candidate; }
    }
    return nil;
}

// Builds an "Open Link in New Tab" item wired to -openLinkInNewTab:. Falls
// back to the DOM-resolved _contextLinkURL when the caller passed no payload.
- (NSMenuItem *)openInNewTabItemWithURLString:(nullable NSString *)url {
    if (!url.length) { url = _contextLinkURL; }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open Link in New Tab"
                                                  action:@selector(openLinkInNewTab:)
                                           keyEquivalent:@""];
    item.enabled = (url.length > 0);
    item.target = self;
    item.representedObject = @{ @"action": @"openLinkNewTab", @"url": url ?: @"" };
    return item;
}

// Translates the Foundation-only tree descriptors into NSMenuItems. Items that
// the engine already provides (Back/Forward/Reload) are skipped so they are not
// duplicated; the detected link URL is attached to the link actions.
- (NSArray<NSMenuItem *> *)vimbActionItemsFromTree:(NSArray<NSDictionary *> *)tree
                                           linkURL:(nullable NSString *)linkURL {
    static NSSet<NSString *> *engineProvided = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // back/forward/reload are in the WK default menu; when a link is present
        // WK also provides Copy Link and an open-item that willOpenMenu converts
        // into "Open Link in New Tab" — so these are not duplicated here.
        engineProvided = [NSSet setWithArray:@[
            @"back", @"forward", @"reload", @"openLinkNewTab", @"copyLink"
        ]];
    });
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *node in tree) {
        if ([node[@"type"] isEqualToString:@"separator"]) {
            if (items.count) { [items addObject:[NSMenuItem separatorItem]]; }
            continue;
        }
        NSString *action = node[@"action"];
        if ([engineProvided containsObject:action]) { continue; }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:node[@"title"]
                                                      action:@selector(dispatchContextAction:)
                                               keyEquivalent:@""];
        item.target = self;
        item.enabled = [node[@"enabled"] boolValue];
        item.representedObject = @{ @"action": action, @"url": linkURL ?: @"" };
        [items addObject:item];
    }
    // Drop a leading separator left over if the first real item was skipped.
    if ([items.firstObject isSeparatorItem]) { [items removeObjectAtIndex:0]; }
    if ([items.lastObject isSeparatorItem]) { [items removeLastObject]; }
    return items;
}

// Builds the "Inspect Element" replacement that opens vimb's own DOM
// inspector tab (same as gF). WK's native frontend window is broken on this
// macOS (see willOpenMenu), so the context-menu entry is rewired to the
// in-app inspector.
- (NSMenuItem *)domInspectorItem {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Inspect Element"
                                                  action:@selector(openDOMInspector:)
                                           keyEquivalent:@""];
    item.target = self;
    item.enabled = YES;
    return item;
}

- (void)openDOMInspector:(id)sender {
    (void)sender;
    id<VimDelegate> d = [self vbVimDelegate];
    if (d && [d respondsToSelector:@selector(vimViewInspector)]) {
        [d vimViewInspector];
    }
}

- (void)openLinkInNewTab:(id)sender {
    NSDictionary *payload = [(NSMenuItem *)sender representedObject];
    NSString *url = payload[@"url"];
    if (!url.length) { return; }
    id<VimDelegate> d = [self vbVimDelegate];
    if (d && [d respondsToSelector:@selector(vimOpenURL:inNewTab:)]) {
        [d vimOpenURL:url inNewTab:YES];
    }
}

// Shared handler for the vimb browser actions appended to the context menu.
- (void)dispatchContextAction:(id)sender {
    NSDictionary *payload = [(NSMenuItem *)sender representedObject];
    NSString *action = payload[@"action"];
    id<VimDelegate> d = [self vbVimDelegate];

    if ([action isEqualToString:@"copyLink"]) {
        [self copyString:payload[@"url"] ?: @""];
    } else if ([action isEqualToString:@"copyPageURL"]) {
        [self copyString:self.URL.absoluteString ?: @""];
    } else if ([action isEqualToString:@"home"]) {
        if ([d respondsToSelector:@selector(vimOpenHomePage:)]) { [d vimOpenHomePage:NO]; }
    } else if ([action isEqualToString:@"hintLinks"]) {
        [self toggleHints:@"o" gmode:NO];
    } else if ([action isEqualToString:@"viewSource"]) {
        if ([d respondsToSelector:@selector(vimViewSource)]) { [d vimViewSource]; }
    } else if ([action isEqualToString:@"addBookmark"]) {
        NSString *url = self.URL.absoluteString ?: @"";
        NSString *title = self.title ?: @"";
        // The vim delegate (BrowserWindowController) is also the VimbExActor
        // that owns :bma; reuse its bookmark add so context-menu behaviour and
        // the ex command stay identical.
        id<VimbExActor> actor = (id<VimbExActor>)d;
        if ([actor respondsToSelector:@selector(exBookmarkAdd:title:)]) {
            [actor exBookmarkAdd:url title:title];
        }
    }
}

- (void)copyString:(NSString *)string {
    if (!string.length) { return; }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:string forType:NSPasteboardTypeString];
}

// The vim delegate (the BrowserWindowController) through which browser actions
// that live there are reached; mirrors how keyDown: reaches the controller.
- (id<VimDelegate>)vbVimDelegate {
    VimController *vim = [self.vbDelegate vimControllerForView:self];
    return vim ? vim.delegate : nil;
}

#pragma mark - Hint mode

// The full hint-mode JS overlay. This is a faithful port of src/scripts/hints.js:
// it picks the hint elements per the mode's xpath family, labels them with a
// shared base-26 labeler, filters them per key, moves focus with Tab/Shift-Tab,
// removes the last filter char with Backspace, fires on Enter and on a unique
// match, and reports results back to native via the `vimb` message bus. The old
// click-only "hintyank"/"hintopen" protocol is replaced by a unified
// `hintdata` message with a `mode`/`value`/`action` payload.
- (void)toggleHints:(NSString *)followMode gmode:(BOOL)gmode {
    if (followMode.length == 0) {
        // Plain toggle: tear down any active overlay.
        [self evaluateJavaScript:@"if(window.__vimb_hint_active){window.__vimb_hint_cleanup(true);}"
                   completionHandler:nil];
        return;
    }
    NSString *js = [self hintOverlayScriptForMode:followMode gmode:gmode];
    // Use the configured hint-keys alphabet (default a..z) instead of the
    // hardcoded base-26 list, matching setting.c 'hint-keys'.
    NSString *keys = [[VimbConfig shared] getString:@"hint-keys" defaultValue:@"abcdefghijklmnopqrstuvwxyz"];
    if (keys.length == 0) { keys = @"abcdefghijklmnopqrstuvwxyz"; }
    NSMutableArray *chars = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.length && chars.count < 36; i++) {
        NSString *ch = [keys substringWithRange:NSMakeRange(i, 1)];
        if (![chars containsObject:ch]) { [chars addObject:[NSString stringWithFormat:@"'%@'", ch]]; }
    }
    NSString *alphaLit = [NSString stringWithFormat:@"var alpha=[%@];", [chars componentsJoinedByString:@","]];
    NSString *oldAlpha = @"var alpha=['a','b','c','d','f','g','h','j','k','l','m','n','p','q','r','s','t','u','v','w','x','y','z'];";
    if ([js containsString:oldAlpha]) {
        js = [js stringByReplacingOccurrencesOfString:oldAlpha withString:alphaLit];
    }
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)toggleHints {
    [self toggleHints:nil];
}

- (void)toggleHints:(NSString *)followMode {
    [self toggleHints:followMode gmode:NO];
}

- (void)sendHintKey:(NSString *)key {
    [self sendHintKey:key mode:nil];
}

- (void)sendHintKey:(NSString *)key mode:(NSString *)followMode {
    NSString *ks = [key stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *js2 = [NSString stringWithFormat:
        @"if(window.__vimb_hint_active){window.__vimb_hint_type('%@')}", ks];
    [self evaluateJavaScript:js2 completionHandler:nil];
    (void)followMode;
}

- (void)hintClear {
    [self evaluateJavaScript:@"if(window.__vimb_hint_active){window.__vimb_hint_clear();}" completionHandler:nil];
}
- (void)hintFocus:(BOOL)back {
    NSString *js = [NSString stringWithFormat:@"if(window.__vimb_hint_active){window.__vimb_hint_focus(%@)}", back ? @"true" : @"false"];
    [self evaluateJavaScript:js completionHandler:nil];
}
- (void)hintBackspace {
    [self evaluateJavaScript:@"if(window.__vimb_hint_active){window.__vimb_hint_backspace();}" completionHandler:nil];
}
- (void)hintFire {
    [self evaluateJavaScript:@"if(window.__vimb_hint_active){window.__vimb_hint_fire();}" completionHandler:nil];
}

// Builds the self-contained, guarded hint-overlay script for the given mode
// and g-mode (keep-open) flag. Source lives in scripts/hintoverlay.js
// (structure ported from src/scripts/hints.js); the two __VIMB_*__ tokens are
// substituted here at runtime.
- (NSString *)hintOverlayScriptForMode:(NSString *)mode gmode:(BOOL)gmode {
    NSString *g = gmode ? @"true" : @"false";
    return [[kVimbScriptHintoverlay
        stringByReplacingOccurrencesOfString:@"__VIMB_MODE__" withString:mode]
        stringByReplacingOccurrencesOfString:@"__VIMB_KEEPOPEN__" withString:g];
}

- (void)scrollToTop { [self evaluateJavaScript:@"window.__vimb.scrollToTop()" completionHandler:nil]; }
- (void)scrollToBottom { [self evaluateJavaScript:@"window.__vimb.scrollToBottom()" completionHandler:nil]; }
- (void)scrollBy:(double)dx y:(double)dy {
    NSString *js = [NSString stringWithFormat:@"window.__vimb.scrollBy(%f,%f)", dx, dy];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)scrollToPercent:(NSUInteger)percent {
    NSString *js = [NSString stringWithFormat:
        @"(function(){var e=document.scrollingElement||document.documentElement;"
        @"var max=Math.max(e.scrollHeight-window.innerHeight,0);"
        @"e.scrollTop=max*%lu/100;window.scrollTo(0,e.scrollTop);})()", (unsigned long)percent];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)scrollToMiddle {
    [self evaluateJavaScript:@"(function(){var e=document.scrollingElement||document.documentElement;"
        @"var max=Math.max(e.scrollHeight-window.innerHeight,0);e.scrollTop=max/2;window.scrollTo(0,max/2);})()"
        completionHandler:nil];
}

- (void)scrollToX:(double)x {
    NSString *js = [NSString stringWithFormat:@"(function(){var e=document.scrollingElement||document.documentElement;"
        @"e.scrollLeft=%f;window.scrollTo(%f,0);})()", x, x];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)scrollToXEnd {
    [self evaluateJavaScript:@"(function(){var e=document.scrollingElement||document.documentElement;"
        @"e.scrollLeft=e.scrollWidth;window.scrollTo(e.scrollLeft,0);})()" completionHandler:nil];
}

- (void)findNextDirection:(BOOL)forward {
    if (_lastQuery.length) {
        [self findString:_lastQuery forwardDirection:forward];
    }
}

- (void)focusLastActiveElement {
    [self evaluateJavaScript:
        @"if (typeof vimb_input_mode_element !== 'undefined' && vimb_input_mode_element) { vimb_input_mode_element.focus(); }"
        completionHandler:nil];
}

- (void)focusFirstInput {
    [self evaluateJavaScript:@"(function(){var e=document.querySelector('input,textarea,[contenteditable=true]');"
        @"if(e)e.focus();})()" completionHandler:nil];
}

- (void)getScrollTopWithCompletion:(void (^)(double top))completion {
    [self evaluateJavaScript:@"(window.__vimScrollTop!=null?window.__vimScrollTop:(document.scrollingElement||document.documentElement).scrollTop||0)"
           completionHandler:^(id result, NSError *error) {
        double top = 0;
        if (!error && result && ![result isKindOfClass:[NSNull class]]) {
            top = [result doubleValue];
        }
        if (completion) { completion(top); }
    }];
}

- (void)scrollToY:(double)y {
    NSString *js = [NSString stringWithFormat:@"(function(){var e=document.scrollingElement||document.documentElement;"
        @"e.scrollTop=%f;window.scrollTo(0,%f);window.__vimScrollTop=%f;})()", y, y, y];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)jumpToURI:(NSString *)uri withY:(double)y {
    NSURL *url = [NSURL URLWithString:uri];
    if (!url) { return; }
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:@"(function(){"  // no-op; load happens natively
        @"})()" completionHandler:^(id result, NSError *err) {
        (void)result; (void)err;
        [weakSelf loadRequest:[NSURLRequest requestWithURL:url]];
    }];
    // Remember the y to restore after load via a stored pending scroll.
    _pendingMarkY = y;
}

- (void)incrementURI:(NSInteger)delta {
    NSString *js = [NSString stringWithFormat:
        @"(function(){var c=%ld,on,nn,m=location.href.match(/(.*?)(\\d+)(\\D*)$/);"
        @"if(m){on=m[2];nn=String(Math.max(parseInt(on)+c,0));"
        @"if(/^0/.test(on)){while(nn.length<on.length){nn='0'+nn;}}"
        @"m[2]=nn;location.href=m.slice(1).join('');}})()", (long)delta];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (void)findString:(NSString *)query forwardDirection:(BOOL)forward {
    if (query.length == 0) { return; }
    _lastQuery = [query copy];
    WKFindConfiguration *cfg = [[WKFindConfiguration alloc] init];
    cfg.backwards = !forward;
    cfg.caseSensitive = NO;
    cfg.wraps = YES;
    [self findString:query withConfiguration:cfg completionHandler:^(WKFindResult *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            id<KeyboardWebViewDelegate> d = self.vbDelegate;
            if (d && [d respondsToSelector:@selector(webView:didReceiveMessage:)]) {
                [d webView:self didReceiveMessage:@{@"t": @"find", @"found": @(result.matchFound)}];
            }
        });
    }];
}

- (void)executeCommand:(NSString *)line {
    // Reserved for future expansion of vimb ex commands that need to run JS
    // against the page (e.g. :js). Currently unused.
    (void)line;
}

@end

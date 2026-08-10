#import "KeyboardWebView.h"
#import "VimbConfig.h"
#import "VimbAutocmd.h"

// This view is created programmatically only (no nibs/coders), so the
// designated-initializer consistency warnings don't apply.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// A tiny embedded JS helper injected as a user script. It provides scroll
// primitives and a message bus bridged back to native via window.webkit.
static NSString *const GVimJS =
    @"window.__vimb = (function(){"
     "  function post(msg){"
     "    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimb){"
     "      window.webkit.messageHandlers.vimb.postMessage(msg);"
     "    }"
     "  }"
      "  function scrollElement(el){"
      "    var n = el, depth = 0;"
      "    for (;n && depth < 40; n=n.parentElement, depth++){"
      "      if (n.scrollHeight > n.clientHeight + 1 || n.scrollWidth > n.clientWidth + 1){ return n; }"
      "    }"
      "    return null;"
      "  }"
      "  function isEditable(t){"
      "    var n=t, d=0;"
      "    if(!n||!n.tagName)return false;"
      "    var tag=(n.tagName||'').toLowerCase();"
      "    if(tag==='textarea'||tag==='input'&&['text','search','url','password','email','tel','number'].indexOf((n.type||'').toLowerCase())>-1)return true;"
      "    if(tag==='input'||tag==='select')return false;"
      "    for(;n&&d<4;n=n.parentElement,d++){"
      "      if(n.isContentEditable||(n.getAttribute&&n.getAttribute('contenteditable')==='true'))return true;"
      "    }"
      "    return false;"
      "  }"
      "  window.__vb_editable=function(){ return isEditable(document.activeElement); };"
      "  var lastFocused;"
      "  document.addEventListener('focusin',function(e){"
      "    var el=e.target;"
      "    if(isEditable(el)){ window.__vb_editable_active=1; post({t:'focusactive'}); }"
      "    else { window.__vb_editable_active=0; }"
      "    lastFocused=el;"
      "  },true);"
      "  document.addEventListener('focusout',function(e){"
      "    if(isEditable(e.target)){ window.__vb_editable_active=0; }"
      "  },true);"
      "  return {"
     "    scrollToTop:function(){ var s = scrollElement(document.scrollingElement || document.documentElement);"
     "        var e = document.scrollingElement || document.documentElement;"
     "        e.scrollTop = 0; window.scrollTo(0,0); post({t:'scrollTop'}); },"
     "    scrollToBottom:function(){ var e = document.scrollingElement || document.documentElement;"
     "        e.scrollTop = e.scrollHeight; window.scrollTo(0, e.scrollHeight); post({t:'scrollBottom'}); },"
     "    scrollBy:function(dx,dy){"
     "        var s = scrollElement(document.activeElement);"
     "        var e = s || (document.scrollingElement || document.documentElement);"
     "        var nx = (e.scrollLeft||0)+dx, ny = (e.scrollTop||0)+dy;"
     "        if (s){ try{ s.scrollBy(dx,dy); }catch(_){} } else { window.scrollBy(dx,dy); }"
     "        post({t:'scrolled', left:nx, top:ny}); },"
     "    pageTop:function(){ try{ window.webkit.messageHandlers.vimb.postMessage({t:'ping'}); }catch(_){} }"
     "  };"
     "})();";

@implementation KeyboardWebView {
    NSString *_lastQuery;
    BOOL _editableFocusActive;
    double _pendingMarkY;
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
    [prefs setValue:@([cfg getInt:@"font-size" defaultValue:16]) forKey:@"minimumFontSize"];
    [prefs setValue:@([cfg getInt:@"font-size" defaultValue:16]) forKey:@"defaultFontSize"];
    [prefs setValue:@([cfg getInt:@"minimum-font-size" defaultValue:0]) forKey:@"minimumFontSize"];

    // Note: no KVC setValue: on WKPreferences for private keys here — setting
    // mediaPlaybackRequiresUserGesture/mediaPlaybackAllowsInline via KVC during
    // configuration blocked WKWebView init (seen as an app launch hang). Only
    // the public preferences above are applied.
    config.defaultWebpagePreferences.allowsContentJavaScript =
        [cfg getBool:@"scripts" defaultValue:YES];

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:GVimJS
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
        self.UIDelegate = nil;
        self.allowsBackForwardNavigationGestures = YES;
        [self addObserver:self forKeyPath:@"estimatedProgress" options:0 context:NULL];
        [self addObserver:self forKeyPath:@"title" options:0 context:NULL];
        [self addObserver:self forKeyPath:@"URL" options:0 context:NULL];
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
        // A text input is focused: allow typing to reach the page. ESC blurs
        // the field and returns to vim normal mode.
        NSString *cs = event.charactersIgnoringModifiers;
        if (cs.length && [cs characterAtIndex:0] == 27) {
            [self evaluateJavaScript:@"document.activeElement&&document.activeElement.blur?document.activeElement.blur():0;"
                      completionHandler:nil];
            _editableFocusActive = NO;
            return;
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

#pragma mark - Script messages (JS -> native)

- (void)userContentController:(WKUserContentController *)uc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"vimb"]) { return; }
    if ([message.body isKindOfClass:[NSDictionary class]]) {
        NSDictionary *body = (NSDictionary *)message.body;
        // Track text-input focus so keys pass through to the page.
        if ([body[@"t"] isEqualToString:@"focusactive"]) {
            _editableFocusActive = YES;
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
    download.delegate = self;
    [[VimbConfig shared].autocmd fireEvent:VAuDownloadStarted uri:self.URL.absoluteString];
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

// Builds the self-contained, guarded hint-overlay script for the given mode and
// g-mode (keep-open) flag. Structure ported from src/scripts/hints.js.
- (NSString *)hintOverlayScriptForMode:(NSString *)mode gmode:(BOOL)gmode {
    NSString *g = gmode ? @"true" : @"false";
    return [NSString stringWithFormat:
        @"(function(){"
        @"'use strict';"
        @"function post(m){if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vimb){window.webkit.messageHandlers.vimb.postMessage(m);}}"
        @"if(window.__vimb_hint_active){window.__vimb_hint_cleanup(true);return;}"
        @"var mode='%@';var keepOpen=%@;"
        @"var alpha=['a','b','c','d','f','g','h','j','k','l','m','n','p','q','r','s','t','u','v','w','x','y','z'];"
        @"function lab(i){var s='',r=i;do{s=alpha[r%%alpha.length]+s;r=Math.floor(r/alpha.length)-1;}while(r>=0);return s;}"
        // Per-mode behaviour (faithful to hints.js xpath/action/handleForm maps).
        @"var xpath,dataMode=false,yankText=false,removeMode=false,openMode=false,handlesForm=false;"
        @"if('otY'.indexOf(mode)>=0){xpath='linkform';openMode=(mode==='o'||mode==='t');yankText=(mode==='Y');}"
        @"else if(mode==='k'){xpath='div';removeMode=true;}"
        @"else if(mode==='e'){xpath='edit';dataMode=true;}"
        @"else if('iI'.indexOf(mode)>=0){xpath='img';dataMode=true;}"
        @"else{xpath='linkimg';dataMode=true;}"
        @"if('eot'.indexOf(mode)>=0)handlesForm=true;"
        // Map the xpath family to a CSS selector that approximates it.
        @"var sel='a[href],button,input:not([type=hidden]),select,summary,[onclick],[tabindex],[role=link],[role=button],[class=lk]';"
        @"if(xpath==='linkimg')sel='a[href],iframe[src],img[src]:not(a img)';"
        @"else if(xpath==='img')sel='img[src]';"
        @"else if(xpath==='div')sel='div';"
        @"else if(xpath==='edit')sel='input:not([type]),input[type=text],textarea';"
        @"function isVisible(e){if(!e)return false;var r=e.getBoundingClientRect();if(!r)return false;"
        @"if(r.bottom<0||r.right<0||r.top>window.innerHeight||r.left>window.innerWidth)return false;"
        @"var s=window.getComputedStyle(e);return !s||(s.display!=='none'&&s.visibility!=='hidden');}"
        @"var seen={};"
        @"var els=Array.prototype.slice.call(document.querySelectorAll(sel)).filter(function(e){if(seen[e]||!isVisible(e))return false;seen[e]=1;return true;});"
        @"if(els.length===0){post({t:'hintnone'});return;}"
        @"window.__vimb_hint_active=1;window.__vimb_hint_els=els;window.__vimb_hint_match='';window.__vimb_hint_activeIdx=null;window.__vimb_hint_vis=[];"
        @"window.__vimb_hint_mode=mode;window.__vimb_hint_keepopen=keepOpen;"
        @"var css=document.createElement('style');css.id='vimb-hint-css';"
        @"css.textContent='.vimb-hint-el{position:absolute;z-index:2147483647;padding:1px 4px;background:rgba(255,210,0,.95);color:#000;border-radius:2px;font:bold 12px monospace;pointer-events:none;box-shadow:0 1px 2px rgba(0,0,0,.3)}';"
        @"(document.head||document.documentElement).appendChild(css);"
        @"window.__vimb_hint_labels=els.map(function(el,i){"
        @"var r=el.getBoundingClientRect();var d=document.createElement('div');d.className='vimb-hint-el';d.textContent=lab(i);"
        @"d.setAttribute('data-i',String(i));d.style.left=(r.left-window.pageXOffset+4)+'px';d.style.top=(r.top-window.pageYOffset+4)+'px';"
        @"(document.body||document.documentElement).appendChild(d);return d;});"
        @"window.__vimb_hint_cleanup=function(){(window.__vimb_hint_labels||[]).forEach(function(d){try{d.remove();}catch(e){}});"
        @"var s=document.getElementById('vimb-hint-css');if(s)s.remove();"
        @"window.__vimb_hint_labels=[];window.__vimb_hint_els=[];window.__vimb_hint_match='';window.__vimb_hint_vis=[];window.__vimb_hint_activeIdx=null;window.__vimb_hint_active=0;};"
        @"function L(d){var i=+d.getAttribute('data-i'),s='',r=i;do{s=alpha[r%%alpha.length]+s;r=Math.floor(r/alpha.length)-1;}while(r>=0);return s;}"
        @"function getSrc(e){if(!e)return '';if(e.href)return e.href;if(e.src)return e.src;if(e.getAttribute){var a=e.getAttribute('href');if(a)return a;a=e.getAttribute('src');if(a)return a;}return '';}"
        // fire: performs the per-mode action and reports it to native.
        @"function fire(idx){var e=window.__vimb_hint_els[idx];if(!e)return;var out=null;"
        @"function data(){return {action:'DATA',value:getSrc(e)};}"
        @"function done(){return {action:'DONE',value:getSrc(e)};}"
        @"if(handlesForm){var tag=(e.nodeName||'').toLowerCase(),type=(e.type||'').toLowerCase();"
        @"if(tag==='input'||tag==='textarea'||tag==='select'){"
        @"if(type==='radio'||type==='checkbox'){try{e.focus();e.click();}catch(_){}}"
        @"else if(type==='submit'||type==='reset'||type==='button'||type==='image'){try{e.click();}catch(_){}}"
        @"else{try{e.focus();}catch(_){}out={action:'INSERT',value:getSrc(e)};}}"
        @"else if(tag==='iframe'||tag==='frame'){try{e.focus();}catch(_){}out=done();}"
        @"else if(removeMode){e.remove();out=done();}"
        @"else if(yankText){out=data();}"
        @"else if(openMode){if(mode==='t'){out=data();}else{try{e.click();}catch(_){}out=done();}}"
        @"else if(dataMode){out=data();}"
        @"}else{"
        @"if(removeMode){e.remove();out=done();}"
        @"else if(yankText){out=data();}"
        @"else if(openMode){if(mode==='t'){out=data();}else{try{e.click();}catch(_){}out=done();}}"
        @"else if(dataMode){out=data();}"
        @"}"
        @"if(yankText&&out){var tv=(e.textContent||'').replace(/\\s+/g,' ').replace(/^\\s+/,'').replace(/\\s+$/,'');out.value=tv;}"
        @"if(out){post({t:'hintdata',mode:mode,value:out.value==null?'':String(out.value),action:out.action});}"
        @"if(keepOpen){window.__vimb_hint_match='';show();}else{window.__vimb_hint_cleanup();}"
        @"}"
        // show: recompute visible labels from the filter text, manage focus.
        @"function show(){var m=window.__vimb_hint_match;var vis=[];"
        @"window.__vimb_hint_labels.forEach(function(d){var i=+d.getAttribute('data-i');var on=(m.length===0||L(d).indexOf(m)===0);d.style.display=on?'':'none';if(on)vis.push(i);});"
        @"window.__vimb_hint_vis=vis;"
        @"if(window.__vimb_hint_activeIdx==null||vis.indexOf(window.__vimb_hint_activeIdx)<0){window.__vimb_hint_activeIdx=vis.length?vis[0]:null;}"
        @"if(m.length&&vis.length===1){fire(vis[0]);}"
        @"else if(m.length&&vis.length===0){post({t:'hintpending',n:0});window.__vimb_hint_cleanup();}"
        @"else{post({t:vis.length?'hintready':'hintnone',n:vis.length});}"
        @"}"
        @"window.__vimb_hint_type=function(ch){window.__vimb_hint_match+=String(ch);show();};"
        @"window.__vimb_hint_backspace=function(){if(window.__vimb_hint_match.length){window.__vimb_hint_match=window.__vimb_hint_match.slice(0,-1);show();}};"
        @"window.__vimb_hint_focus=function(back){var vis=window.__vimb_hint_vis;if(!vis||!vis.length)return;var idx=vis.indexOf(window.__vimb_hint_activeIdx);if(idx<0)idx=0;"
        @"if(back){idx--;if(idx<0)idx=vis.length-1;}else{idx++;if(idx>=vis.length)idx=0;}window.__vimb_hint_activeIdx=vis[idx];};"
        @"window.__vimb_hint_fire=function(){var i=window.__vimb_hint_activeIdx;if(i!=null&&window.__vimb_hint_els[i])fire(i);};"
        @"window.__vimb_hint_clear=function(){post({t:'hintnone'});window.__vimb_hint_cleanup();};"
        @"show();"
        @"})();", mode, g];
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

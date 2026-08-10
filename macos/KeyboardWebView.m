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

    // Additional webkit settings mapped via KVC where WKPreferences exposes
    // the (sometimes private) backing key. Guarded so unknown keys no-op.
    NSDictionary<NSString *, NSNumber *> *kv = @{
        @"javascriptEnabled": @([cfg getBool:@"scripts" defaultValue:YES]),
        @"javaScriptCanAccessClipboard": @([cfg getBool:@"javascript-can-access-clipboard" defaultValue:NO]),
        @"mediaPlaybackRequiresUserGesture": @([cfg getBool:@"media-playback-requires-user-gesture" defaultValue:NO]),
        @"mediaPlaybackAllowsInline": @([cfg getBool:@"media-playback-allows-inline" defaultValue:YES]),
        @"backForwardCacheEnabled": @YES,
    };
    for (NSString *k in kv.keyEnumerator) {
        id v = [prefs valueForKey:k];
        if ([prefs respondsToSelector:NSSelectorFromString(k)] || v != nil) {
            @try { [prefs setValue:kv[k] forKey:k]; } @catch (NSException *e) {}
        }
    }
    // caret browsing
    if ([cfg getBool:@"caret" defaultValue:NO]) {
        @try { [prefs setValue:@YES forKey:@"caretBrowsingEnabled"]; } @catch (NSException *e) {}
    }
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
    NSURL *dir = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"] isDirectory:YES];
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

- (void)toggleHints {
    [self toggleHints:nil];
}

- (void)toggleHints:(NSString *)followMode {
    // Map hint-mode char to a numeric action used by the JS overlay.
    int modeCode = 0;                       // f/o -> click (follow)
    if ([followMode isEqualToString:@"t"])      { modeCode = 2; } // new tab
    else if ([followMode isEqualToString:@"o"]) { modeCode = 0; } // open
    else if ([followMode isEqualToString:@"y"]) { modeCode = 3; } // yank url
    else if ([followMode isEqualToString:@"i"]) { modeCode = 4; } // focus element
    NSString *js =
        @"(function(){"
        @" if(window.__vimb_hint_active){window.__vimb_hint_cleanup();return;}"
        @" var alpha=['a','b','c','d','f','g','h','j','k','l','m','n','p','q','r','s','t','u','v','w','x','y','z'];"
        @" var mse=%d;"   // mode flag: 0..n
        @" window.__vimb_hint_alpha=alpha;"
        @" function lab(i){var s='',r=i;do{s=alpha[r%alpha.length]+s;r=Math.floor(r/alpha.length)-1;}while(r>=0);return s;}"
        @" var sel='a[href],img,button,input[type=submit],input[type=button],textarea';"
        @" var els=Array.prototype.slice.call(document.querySelectorAll(sel));"
        @" if(els.length===0){window.webkit.messageHandlers.vimb.postMessage({t:'hintnone'});return;}"
        @" window.__vimb_hint_els=els;"
        @" window.__vimb_hint_match='';"
        @" window.__vimb_hint_mode=mse;"
        @" var css=document.createElement('style');css.id='vimb-hint-css';"
        @" css.textContent='.vimb-hint-el{position:absolute;z-index:2147483647;padding:1px 4px;"
        @"   background:rgba(255,210,0,.95);color:#000;border-radius:2px;font:bold 12px monospace;"
        @"   pointer-events:none;box-shadow:0 1px 2px rgba(0,0,0,.3)}';"
        @" document.documentElement.appendChild(css);"
        @" window.__vimb_hint_labels=els.map(function(el,i){"
        @"   var r=el.getBoundingClientRect();var d=document.createElement('div');d.className='vimb-hint-el';"
        @"   d.textContent=lab(i);d.setAttribute('data-i',String(i));"
        @"   d.style.left=(r.left-window.pageXOffset+4)+'px';d.style.top=(r.top-window.pageYOffset+4)+'px';"
        @"   document.body==null?document.documentElement.appendChild(d):document.body.appendChild(d);return d;});"
        @" window.__vimb_hint_cleanup=function(){"
        @"   (window.__vimb_hint_labels||[]).forEach(function(d){try{d.remove();}catch(e){}});"
        @"   var s=document.getElementById('vimb-hint-css');if(s)s.remove();"
        @"   window.__vimb_hint_labels=[];window.__vimb_hint_els=[];window.__vimb_hint_match='';"
        @"   window.__vimb_hint_active=0;};"
        @" window.__vimb_hint_follow=function(idx){"
        @"   var el=window.__vimb_hint_els[idx];"
        @"   if(!el)return;"
        @"   var mode=window.__vimb_hint_mode;"
        @"   if(mode==4){try{el.focus();}catch(e){} }"           // i
        @"   else if(mode==3){var u=el.href||el.src||el.value||location.href;" // y
        @"       window.webkit.messageHandlers.vimb.postMessage({t:'hintyank',url:u});}"
        @"   else if(mode==2){var u=el.href||el.src||'';"        // t (new tab)
        @"       window.webkit.messageHandlers.vimb.postMessage({t:'hintopen',url:u});"
        @"       if(u){return;} }"                                // keep hints open in vimb
        @"   else{try{el.click();}catch(e){}}"
        @"   window.__vimb_hint_cleanup();"
        @" };"
        @" window.__vimb_hint_type=function(ch){"
        @"   window.__vimb_hint_match+=String(ch);var m=window.__vimb_hint_match;"
        @"   var labs=window.__vimb_hint_labels;"
        @"   if(m.length>1&&window.__vimb_hint_used==null){"
        @"     window.__vimb_hint_used=1;"
        @"     var seen={};var dups=0;"
        @"     labs.forEach(function(d){var L=lab(+d.getAttribute('data-i')).substr(0,m.length-1);"
        @"       seen[L]=seen[L]?seen[L]+1:1;});"
        @"   }"
        @"   function L(d){var i=+d.getAttribute('data-i'),s='',r=i;"
        @"      do{s=window.__vimb_hint_alpha[r%window.__vimb_hint_alpha.length]+s;"
        @"          r=Math.floor(r/window.__vimb_hint_alpha.length)-1;}while(r>=0);return s;}"
        @"   var vis=labs.filter(function(d){return L(d).indexOf(m)===0;});"
        @"   labs.forEach(function(d){var on=L(d).indexOf(m)===0;d.style.display=on?'':'none';});"
        @"   if(vis.length===1){var idx=+vis[0].getAttribute('data-i');"
        @"       window.__vimb_hint_follow(idx);}"
        @"   else if(vis.length===0){window.__vimb_hint_cleanup();}"
        @"   else{window.webkit.messageHandlers.vimb.postMessage({t:'hintpending',n:vis.length});}"
        @" };"
        @" window.__vimb_hint_active=1;window.__vimb_hint_used=null;"
        @" window.webkit.messageHandlers.vimb.postMessage({t:'hintready',n:els.length});"
        @"})();";
    // modeCode: f/o=0(click), t=2, y=3, i=4
    NSString *final = [js stringByReplacingOccurrencesOfString:@"%d"
             withString:[NSString stringWithFormat:@"%d", (int)modeCode]];
    [self evaluateJavaScript:final completionHandler:nil];
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

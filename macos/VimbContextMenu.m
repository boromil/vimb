// VimbContextMenu.m — Foundation-only context-menu tree builder (parity with
// src/context-menu.c). The GTK client keeps WebKitGTK's default menu and only
// replaces "open … in new window" items with "open … in new tab" (plus the
// surrounding browser actions). This class models that action tree so the
// AppKit menu in KeyboardWebView can be built and validated without AppKit.
#import "VimbContextMenu.h"

@implementation VimbContextMenu

static NSDictionary *VimbActionItem(NSString *title, NSString *action, BOOL enabled) {
    return @{
        @"type": @"action",
        @"title": title,
        @"action": action,
        @"enabled": @(enabled),
    };
}

static NSDictionary *VimbSeparatorItem(void) {
    return @{ @"type": @"separator" };
}

+ (BOOL)hasLink:(NSDictionary *)ctx {
    if (![ctx isKindOfClass:[NSDictionary class]]) { return NO; }
    NSString *link = ctx[@"link"];
    return [link isKindOfClass:[NSString class]] && link.length > 0;
}

+ (BOOL)isOpenInNewWindowIdentifier:(NSString *)identifier {
    if (identifier.length == 0) { return NO; }
    // WKWebView's default macOS menu identifiers for the "open in new window"
    // family; each has a "open in new tab" / copy counterpart in the builder.
    static NSSet<NSString *> *ids = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ids = [NSSet setWithArray:@[
            @"WKMenuItemIdentifierOpenLinkInNewWindow",
            @"WKMenuItemIdentifierOpenImageInNewWindow",
            @"WKMenuItemIdentifierOpenFrameInNewWindow",
        ]];
    });
    return [ids containsObject:identifier];
}

+ (NSArray<NSDictionary *> *)menuTreeForContext:(NSDictionary *)ctx {
    if (![ctx isKindOfClass:[NSDictionary class]]) { ctx = @{}; }
    BOOL back = [ctx[@"back"] boolValue];
    BOOL forward = [ctx[@"forward"] boolValue];
    // A nil "link" key or an empty string mean "not over a link".
    BOOL linkPresent = [self hasLink:ctx];

    NSArray<NSDictionary *> *navigation = @[
        VimbActionItem(@"Back", @"back", back),
        VimbActionItem(@"Forward", @"forward", forward),
        VimbSeparatorItem(),
        VimbActionItem(@"Reload Page", @"reload", YES),
    ];

    NSArray<NSDictionary *> *context;
    if (linkPresent) {
        context = @[
            VimbSeparatorItem(),
            VimbActionItem(@"Open Link in New Tab", @"openLinkNewTab", YES),
            VimbActionItem(@"Copy Link", @"copyLink", YES),
        ];
    } else {
        context = @[
            VimbSeparatorItem(),
            VimbActionItem(@"Copy Page URL", @"copyPageURL", YES),
        ];
    }

    NSArray<NSDictionary *> *browser = @[
        VimbSeparatorItem(),
        VimbActionItem(@"Home", @"home", YES),
        VimbActionItem(@"Hint Links", @"hintLinks", YES),
        VimbActionItem(@"View Source", @"viewSource", YES),
        VimbActionItem(@"Add Bookmark", @"addBookmark", YES),
    ];

    NSMutableArray *tree = [NSMutableArray arrayWithCapacity:
        navigation.count + context.count + browser.count];
    [tree addObjectsFromArray:navigation];
    [tree addObjectsFromArray:context];
    [tree addObjectsFromArray:browser];
    return tree;
}

@end

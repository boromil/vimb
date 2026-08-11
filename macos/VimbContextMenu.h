// VimbContextMenu.h
//
// Foundation-only builder for the right-click context-menu tree, ported from
// src/context-menu.c. The GTK original relies on WebKitGTK's default menu and
// swaps the "open … in new window" items for "open … in new tab"; on macOS the
// WKWebView default menu is customized in KeyboardWebView (AppKit), which asks
// this class for the vimb action tree and maps each stable action tag to a
// selector. Keeping the tree builder here (Foundation-only) lets it run in the
// unit-test target.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VimbContextMenu : NSObject

// Build the context-menu tree for a right-clicked element.
//
// ctx keys (NSDictionary):
//   @"link"    - NSString * : absolute href under the pointer, or absent/nil.
//   @"back"    - NSNumber * : the web view can go back  (default NO).
//   @"forward" - NSNumber * : the web view can go forward (default NO).
//
// Returns an ordered NSArray of item dictionaries in display order:
//   action:    @{ @"type": @"action",
//                  @"title":  NSString *        (menu label),
//                  @"action": NSString *        (stable tag, see below),
//                  @"enabled": NSNumber *       (BOOL) }
//   separator: @{ @"type": @"separator" }
//
// Stable action tags (parity with the browser actions provided by vimb, which
// on GTK keeps WebKitGTK's default menu and replaces the "open … in new window"
// items with "open … in new tab" — fix_open_in_new_window_stock_action):
//   back, forward, reload,
//   openLinkNewTab, copyLink                       (only when a link is present)
//   copyPageURL                                    (only when no link is present)
//   home, hintLinks, viewSource, addBookmark
+ (NSArray<NSDictionary *> *)menuTreeForContext:(nullable NSDictionary *)ctx;

// Convenience: whether a link is present in the given context.
+ (BOOL)hasLink:(nullable NSDictionary *)ctx;

// Convenience: whether an element identifier from the AppKit menu is one of the
// WKWebView's "open in new window" items we replace with "open in new tab"
// (the macOS analogue of the fix_open_in_new_window_stock_action path).
+ (BOOL)isOpenInNewWindowIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END

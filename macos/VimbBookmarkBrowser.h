#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class VimbBookmarkStore;

// AppKit bookmark browser: a keyboard-first panel presenting the persisted
// bookmark list (parity with the gB flow in src/bookmark.c). Offers
// list + filter-as-you-type, Enter opens the selected bookmark, 'd' deletes it.
//
// NOT a unit-test target (AppKit) — the testable CRUD lives in
// VimbBookmarkStore.
@interface VimbBookmarkBrowser : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

// The shared browser singleton (backed by the real bookmarks file).
+ (instancetype)sharedBrowser;

// Present the browser in a modal panel attached to the key window. Also
// usable as an action from a menu item.
- (IBAction)showBookmarks:(nullable id)sender;
- (void)presentBookmarks;

// Designated initializer: browser showing the given store (used in production
// with the real bookmarks file).
- (instancetype)initWithStore:(VimbBookmarkStore *)store;

@end

NS_ASSUME_NONNULL_END

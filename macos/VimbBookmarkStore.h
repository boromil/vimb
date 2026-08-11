#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A single bookmark entry, mirroring src/bookmark.c's `Bookmark` (uri, title,
// tags). The tags string is whitespace-separated, matching vimb's bookmark
// file format.
@interface VimbBookmark : NSObject
@property(nonatomic, copy) NSString *url;
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, copy, nullable) NSString *tags;
- (instancetype)initWithURL:(NSString *)url title:(nullable NSString *)title tags:(nullable NSString *)tags;
@end

// Foundation-only CRUD/list/lookup store for bookmarks, directly testable in
// the unit-test target (no AppKit). Persists to a plain text file in vimb's
// bookmark format: one entry per line, `uri`, `uri\ttitle`, or
// `uri\ttitle\ttags` (tab separated, mirroring bookmark_add() in bookmark.c).
//
// For backward compatibility with bookmarks already written as `uri title`
// (space separated) it also parses that form back into url+title.
@interface VimbBookmarkStore : NSObject

// Designated initializer: file the store reads/writes.
- (instancetype)initWithPath:(NSString *)path;

// Absolute path to the backing bookmark file.
@property(nonatomic, readonly, copy) NSString *path;

// A store rooted at a freshly-created temp directory (used by unit tests so
// real user data is never touched).
+ (instancetype)storeInTempDirectoryWithName:(NSString *)name;

// --- read ---
@property(nonatomic, readonly, copy) NSArray<VimbBookmark *> *allBookmarks;
// Filtered list matching all whitespace-separated query parts as prefixes
// (parity with bookmark_contains_all_tags / bookmark_fill_completion).
- (NSArray<VimbBookmark *> *)bookmarksMatching:(NSString *)query;
// First bookmark with the given URL, or nil.
- (nullable VimbBookmark *)bookmarkForURL:(NSString *)url;
- (BOOL)containsBookmarkForURL:(NSString *)url;

// --- write ---
- (BOOL)addBookmarkWithURL:(NSString *)url title:(nullable NSString *)title tags:(nullable NSString *)tags;
- (BOOL)removeBookmarkForURL:(NSString *)url;

@end

NS_ASSUME_NONNULL_END

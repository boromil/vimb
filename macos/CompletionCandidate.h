// Foundation-only completion candidate model + matcher (port of src/completion.c
// + util.c util_fill_completion / setting.c setting_fill_completion, the parts
// that generate and filter the candidate list).
//
// This file is deliberately AppKit-free so it can live in the unit-test target.
// The AppKit dropdown rendering lives in CompletionDropdown.m.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// One row in the completion dropdown. Mirrors the two-column CompletionItem
// from src/completion.c: `value` is the first column (the text that gets
// inserted), `detail` is the optional second column (e.g. a URL's title).
@interface CompletionCandidate : NSObject
@property (nonatomic, copy) NSString *value;   // first column - inserted on select
@property (nonatomic, copy, nullable) NSString *detail; // second column - decorative

- (instancetype)initWithValue:(NSString *)value detail:(nullable NSString *)detail;
+ (instancetype)candidateWithValue:(NSString *)value detail:(nullable NSString *)detail;
@end

// Drop-in, Foundation-only replacement for the CompletionItem GOs in
// src/completion.c (a two-column list store).
typedef NSArray<CompletionCandidate *> CompletionList;
NS_SWIFT_NAME(CompletionList)

// Parsed color components from a GTK `completion-*` CSS declaration body
// (e.g. "color:#fff;background-color:#656565;font:..."). Parsing is done in
// Foundation only; the AppKit dropdown builds NSColor from these components.
@interface CompletionStyle : NSObject
@property (nonatomic, readonly) BOOL hasBackground;
@property (nonatomic, readonly) CGFloat bgRed, bgGreen, bgBlue, bgAlpha;
@property (nonatomic, readonly) BOOL hasForeground;
@property (nonatomic, readonly) CGFloat fgRed, fgGreen, fgBlue, fgAlpha;
+ (instancetype)emptyStyle;
// Configure the parsed colors (used by CompletionMatcher.styleFromCSS:).
- (void)setBackgroundColorRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
- (void)setForegroundColorRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
@end

// Candidate generation / ranking / filtering (port of ex.c complete()'s
// prefix filtering, util.c util_fill_completion and setting.c
// setting_fill_completion; all use g_str_has_prefix).
@interface CompletionMatcher : NSObject

// Rank candidate strings for a query: prefix matches first, then any
// substring match, deduplicated, capped at `limit`. When sorted is YES the
// result is additionally ordered lexicographically (ex.c sort=TRUE); when NO
// source order is preserved (history/URL completion, ex.c sort=FALSE).
+ (NSArray<NSString *> *)rankMatchesForQuery:(NSString *)query
                                   inStrings:(NSArray<NSString *> *)strings
                                        limit:(NSUInteger)limit
                                       sorted:(BOOL)sorted;

// Build two-column candidates from a list of value strings (detail nil).
+ (NSArray<CompletionCandidate *> *)candidatesForQuery:(NSString *)query
                                             inStrings:(NSArray<NSString *> *)strings
                                                  limit:(NSUInteger)limit
                                                 sorted:(BOOL)sorted;

// Build candidates from value/detail pairs (dictionaries {"value":..,
// "detail":..}), filtered by the query value and capped.
+ (NSArray<CompletionCandidate *> *)candidatesForQuery:(NSString *)query
                                               entries:(NSArray<NSDictionary<NSString *, NSString *> *> *)entries
                                                  limit:(NSUInteger)limit;

// Strip the leading ':' prompt and whitespace the way src/ex.c complete()
// does before matching: the seeded ':' stays in the field but must not break
// prefix matching, so ":open ex" completes exactly like "open ex".
+ (NSString *)normalizedLine:(NSString *)line;

// The fixed part of a command/search line before the token being completed:
// the prompt char plus any command word — ":", ":open ", "/". Rewriting the
// line as head + candidate preserves everything the user already typed.
+ (NSString *)completionHeadForLine:(NSString *)line;

// Parse a GTK completion-* CSS declaration body into a CompletionStyle.
+ (CompletionStyle *)styleFromCSS:(NSString *)css;
@end

NS_ASSUME_NONNULL_END

// AppKit completion dropdown for vimb (parity with the GTK4 completion widget
// in src/completion.c). A native, opaque popover-style list rendered below a
// command field as the user types.
//
// The candidate *generation / ranking / filtering* logic lives in the
// Foundation-only CompletionMatcher (CompletionCandidate.h) so that it is
// unit-testable; this view is AppKit-coupled and only ships with the app.
//
// Keyboard operation is exposed explicitly so the owning controller can route
// Tab/Shift-Tab/Enter/Esc: moveSelectionBy:+/- steps the highlight, select at
// the current row is read via `selectedValue`, and dismiss ends the session.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class CompletionCandidate;

@interface CompletionDropdown : NSView <NSTableViewDataSource, NSTableViewDelegate>

// CSS declaration bodies for completion-* settings, fed by VimbConfig (the
// GTK " #completion > row{...}" bodies). Empty strings mean "use defaults".
@property (nonatomic, copy, nullable) NSString *completionCSS;
@property (nonatomic, copy, nullable) NSString *completionHoverCSS;
@property (nonatomic, copy, nullable) NSString *completionSelectedCSS;

// Underlying single-column table of candidates.
@property (nonatomic, readonly) NSTableView *tableView;

// The currently highlighted row's value (first column), or nil when nothing is
// selected or the list is empty.
@property (nonatomic, readonly, nullable) NSString *selectedValue;
// The full currently-highlighted candidate, or nil.
@property (nonatomic, readonly, nullable) CompletionCandidate *selectedCandidate;

- (instancetype)initWithFrame:(NSRect)frame;

// Position and size the dropdown to sit just below `anchorInView`, staying
// anchored to it as the window resizes.
- (void)presentRelativeToRect:(NSRect)rect inView:(NSView *)view;

// Replace the candidate list and refresh the shown rows.
- (void)updateWithCandidates:(NSArray<CompletionCandidate *> *)candidates;

// Move the highlight by +1/-1 (Tab/Shift-Tab). GTK parity: stepping past the
// first/last item clears the highlight and returns NO (the caller restores
// the typed text); the next step in the same direction wraps to the far end.
// Returns YES only while the dropdown is visible and has candidates.
- (BOOL)moveSelectionBy:(NSInteger)direction;

// Dismiss/hide the dropdown (Esc / completion end).
- (void)dismiss;

// Whether at least one candidate is shown.
@property (nonatomic, readonly) BOOL hasCandidates;

@end

NS_ASSUME_NONNULL_END

// AppKit completion dropdown for vimb (parity with the GTK4 completion widget
// in src/completion.c). A native, opaque popover-style list floating above the
// command field as the user types.
//
// Rows are laid out manually (no NSScrollView/NSTableView): the table-based
// version fought AppKit's document layout — the scroll view silently resized
// the document and offset row 0 by ~10pt, so rows rendered half-clipped no
// matter how the clip view was reset. Manual layout pins each row to an exact
// 22pt slot with an opaque plate behind them; the list shows the first
// floor(height/kRowHeight) candidates (GTK caps the box at 1/3 of the window
// height the same way).
//
// Colors stay driven by the completion-css / completion-selected-css settings
// (GTK parity: defaults are the #656565 plate with #888 selected rows from
// config.def.h). The candidate *generation / ranking / filtering* logic lives
// in the Foundation-only CompletionMatcher (CompletionCandidate.h) so it stays
// unit-testable; this view is AppKit-coupled and only ships with the app.
//
// Keyboard operation is exposed explicitly so the owning controller can route
// Tab/Shift-Tab/Enter/Esc: moveSelectionBy:+/- steps the highlight, the
// current row is read via `selectedValue`, and dismiss ends the session.
#import "CompletionDropdown.h"
#import "CompletionCandidate.h"
#import <QuartzCore/QuartzCore.h>

// A single completion row: full-row background (normal or selected) with the
// candidate value on the left and an optional dimmed detail on the right
// (GTK CompletionItem first/second pair). Draws itself so the completion-css
// colors are honored exactly (NSTableView selection styling is not).
@interface CompletionRowView : NSView
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) BOOL highlighted;
@property (nonatomic, strong) NSColor *normalBg;
@property (nonatomic, strong) NSColor *selectedBg;
@property (nonatomic, strong) NSColor *normalFg;
@property (nonatomic, strong) NSColor *selectedFg;
@end

@implementation CompletionRowView {
    NSTextField *_valueLabel;
    NSTextField *_detailLabel;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _valueLabel = [[NSTextField alloc] init];
        _valueLabel.editable = NO;
        _valueLabel.selectable = NO;
        _valueLabel.bezeled = NO;
        _valueLabel.drawsBackground = NO;
        _valueLabel.font = [NSFont systemFontOfSize:12.0];
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];

        _detailLabel = [[NSTextField alloc] init];
        _detailLabel.editable = NO;
        _detailLabel.selectable = NO;
        _detailLabel.bezeled = NO;
        _detailLabel.drawsBackground = NO;
        _detailLabel.font = [NSFont systemFontOfSize:11.0];
        _detailLabel.alignment = NSTextAlignmentRight;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingHead;
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_detailLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_detailLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_valueLabel.trailingAnchor constant:8],
        ]];
    }
    return self;
}

- (void)setValue:(NSString *)value { _value = [value copy]; _valueLabel.stringValue = value ?: @""; }
- (void)setDetail:(NSString *)detail {
    _detail = [detail copy];
    _detailLabel.stringValue = detail ?: @"";
    _detailLabel.hidden = (detail.length == 0);
}

- (void)setHighlighted:(BOOL)highlighted {
    _highlighted = highlighted;
    _valueLabel.textColor = highlighted ? (_selectedFg ?: _normalFg) : _normalFg;
    _detailLabel.textColor = [((highlighted ? (_selectedFg ?: _normalFg) : _normalFg)) colorWithAlphaComponent:0.65];
    [self setNeedsDisplay:YES];
}

// Opaque full-row background; drawRect is reliable here (plain subviews, no
// layer-backed scroll sandwich fighting the fill).
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = self.highlighted ? self.selectedBg : self.normalBg;
    [fill setFill];
    NSRectFill(self.bounds);
}

- (BOOL)isFlipped { return YES; }

@end

// Flipped container so row i sits at y = i * kRowHeight from the TOP (plain
// NSView is bottom-left origin; without flipping the candidate order rendered
// upside-down and the highlight painted the wrong row).
@interface CompletionRowsContainer : NSView
@end

@implementation CompletionRowsContainer
- (BOOL)isFlipped { return YES; }
@end

@interface CompletionDropdown () {
    CALayer *_plateLayer;
    NSView *_rowsContainer;   // flipped; holds CompletionRowView slots
}
@property (nonatomic, copy) NSArray<CompletionCandidate *> *candidates;
@property (nonatomic) NSInteger highlightIndex;
@property (nonatomic, strong) NSColor *fgColor;
@property (nonatomic, strong) NSColor *bgColor;
@property (nonatomic, strong) NSColor *selectedBgColor;
@property (nonatomic, strong) NSColor *selectedFgColor;
@end

@implementation CompletionDropdown

static const CGFloat kRowHeight = 22.0;
static const CGFloat kCornerRadius = 8.0;
// The popover floats fully ABOVE the input row with a small gap: its bottom
// edge never touches (let alone overlaps) the command line. GTK stacks the
// completion flush above the input; the native popover chrome (rounded
// corners + shadow) needs breathing room to read as a separate floating
// panel instead of a box glued onto the input bar.
static const CGFloat kAnchorGap = 4.0;
// GTK parity caps the completion at 1/3 of the window height (see
// completion_create: "use max 1/3 of window height for the completion"); this
// is an absolute ceiling on top of that.
static const CGFloat kHardMaxHeight = 300.0;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        // Popover-style chrome: rounded plate, hairline border, soft shadow.
        // The plate itself is a sublayer at the bottom of the layer stack so
        // it composites below every row; the view layer keeps border+shadow.
        self.layer.cornerRadius = kCornerRadius;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        self.layer.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.30].CGColor;
        self.layer.shadowOpacity = 1.0;
        self.layer.shadowRadius = 6.0;
        self.layer.shadowOffset = CGSizeMake(0.0, -2.0);
        _plateLayer = [CALayer layer];
        _plateLayer.cornerRadius = kCornerRadius;
        _plateLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _plateLayer.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
        [self.layer addSublayer:_plateLayer];

        // Flipped container: row i occupies y = i * kRowHeight exactly from
        // the top. No scroll view means no document insets or clip offsets to
        // fight.
        _rowsContainer = [[CompletionRowsContainer alloc] initWithFrame:self.bounds];
        _rowsContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_rowsContainer];

        self.candidates = @[];
        self.highlightIndex = -1;
        [self applyStyles];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [super initWithCoder:coder];
}

- (BOOL)isFlipped { return YES; }

- (void)updateWithCandidates:(NSArray<CompletionCandidate *> *)candidates {
    self.candidates = candidates ?: @[];
    self.highlightIndex = -1;
    [self rebuildRows];
}

// (Re)build the row views for the current candidates. The panel height is
// finalized by presentRelativeToRect:inView:; rows simply fill the container
// top-down and any candidate beyond the visible slots is dropped (the panel
// is already capped at 1/3 window height + 300pt, GTK-style).
- (void)rebuildRows {
    [_rowsContainer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat w = _rowsContainer.bounds.size.width;
    NSUInteger count = self.candidates.count;
    for (NSUInteger i = 0; i < count; i++) {
        CompletionRowView *row = [[CompletionRowView alloc] initWithFrame:NSMakeRect(0, (CGFloat)i * kRowHeight, w, kRowHeight)];
        row.autoresizingMask = NSViewWidthSizable;
        row.value = self.candidates[i].value;
        row.detail = self.candidates[i].detail;
        row.normalBg = self.bgColor;
        row.selectedBg = self.selectedBgColor;
        row.normalFg = self.fgColor;
        row.selectedFg = self.selectedFgColor;
        [row setHighlighted:NO];
        [_rowsContainer addSubview:row];
    }
}

- (void)presentRelativeToRect:(NSRect)rect inView:(NSView *)view {
    NSUInteger count = self.candidates.count;
    if (count == 0) { [self dismiss]; return; }
    // The anchor's origin.y marks the top of the command input row: the list
    // floats fully above it with a small gap (kAnchorGap), growing upward
    // over the page — like vimb GTK, where the completion box stacks above
    // the input line, never covering it. Clamp width/height inside the
    // container so rows can never be clipped by the window boundary or
    // reach into the input row. Height is capped at 1/3 of the container
    // (GTK parity) plus an absolute ceiling.
    // Settle Auto Layout first: the input row expanding (inputRowHeight 0->26)
    // when the command field opens changes the container's height, and
    // measuring stale bounds here once squeezed the list into a fraction of
    // a row (clipped slivers of text over the page).
    [view layoutSubtreeIfNeeded];
    CGFloat x = MAX(0, rect.origin.x);
    CGFloat w = MIN(rect.size.width, view.bounds.size.width - 2 * x);
    // The list grows up from the anchor, so it must also fit between the
    // anchor (plus the floating gap) and the top of the container.
    CGFloat avail = view.bounds.size.height - rect.origin.y - kAnchorGap;
    CGFloat h = MIN(MIN(MIN((CGFloat)count * kRowHeight, view.bounds.size.height / 3.0), kHardMaxHeight), avail);
    if (w < kRowHeight || h <= 0) { [self dismiss]; return; }
    self.frame = NSMakeRect(x, rect.origin.y + kAnchorGap, w, h);
    _rowsContainer.frame = self.bounds;
    // Only as many rows as fit the capped height.
    NSUInteger visible = MIN(count, (NSUInteger)floor(h / kRowHeight));
    if (visible < count) {
        NSArray<CompletionCandidate *> *trimmed = [self.candidates subarrayWithRange:NSMakeRange(0, visible)];
        self.candidates = trimmed;
        [self rebuildRows];
    } else {
        [self rebuildRows];
    }
    self.hidden = NO;
}

- (void)dismiss {
    self.hidden = YES;
    self.highlightIndex = -1;
    // Ending the session drops the candidates too, so `hasCandidates` reflects
    // "completion session active" (GTK FLAG_COMPLETION) rather than "rows were
    // shown at some point".
    self.candidates = @[];
    [_rowsContainer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

- (BOOL)hasCandidates {
    return self.candidates.count > 0;
}

// GTK parity (completion_next): stepping over the first/last item clears the
// highlight and returns NO so the caller can restore the user's typed text;
// the NEXT step in the same direction wraps to the far end.
- (BOOL)moveSelectionBy:(NSInteger)direction {
    NSUInteger count = self.candidates.count;
    if (!self.isHidden && count == 0) { return NO; }
    if (count == 0) { return NO; }
    NSInteger idx = self.highlightIndex;
    if (direction >= 0) {
        idx = (idx == -1) ? 0 : idx + 1;
        if (idx >= (NSInteger)count) { [self deselect]; return NO; }
    } else {
        idx = (idx == -1) ? (NSInteger)count - 1 : idx - 1;
        if (idx < 0) { [self deselect]; return NO; }
    }
    self.highlightIndex = idx;
    [self repaintHighlight];
    return YES;
}

- (void)deselect {
    self.highlightIndex = -1;
    [self repaintHighlight];
}

- (void)repaintHighlight {
    NSArray<NSView *> *rows = _rowsContainer.subviews;
    for (NSUInteger i = 0; i < rows.count; i++) {
        CompletionRowView *row = (CompletionRowView *)rows[i];
        [row setHighlighted:((NSInteger)i == self.highlightIndex)];
    }
}

- (NSString *)selectedValue {
    CompletionCandidate *c = self.selectedCandidate;
    return c.value;
}

- (CompletionCandidate *)selectedCandidate {
    NSInteger idx = self.highlightIndex;
    if (idx < 0 || idx >= (NSInteger)self.candidates.count) { return nil; }
    return self.candidates[idx];
}

#pragma mark - Styling (completion-* CSS)

- (void)setCompletionCSS:(NSString *)completionCSS {
    _completionCSS = [completionCSS copy];
    [self applyStyles];
}
- (void)setCompletionHoverCSS:(NSString *)completionHoverCSS {
    _completionHoverCSS = [completionHoverCSS copy];
    [self applyStyles];
}
- (void)setCompletionSelectedCSS:(NSString *)completionSelectedCSS {
    _completionSelectedCSS = [completionSelectedCSS copy];
    [self applyStyles];
}

- (void)applyStyles {
    CompletionStyle *normal = [CompletionMatcher styleFromCSS:self.completionCSS ?: @""];
    CompletionStyle *selected = [CompletionMatcher styleFromCSS:self.completionSelectedCSS ?: @""];

    // Defaults (opaque, readable) when unset — parity with the default
    // #completion row color:#fff on background:#656565 (config.def.h
    // SETTING_COMPLETION_CSS) and the selected row color:#f6f3e8 on
    // background:#888 (SETTING_COMPLETION_SELECTED_CSS).
    NSColor *bg = [NSColor colorWithCalibratedWhite:0x65 / 255.0 alpha:1.0];
    NSColor *fg = [NSColor whiteColor];
    if (normal.hasBackground) {
        bg = [NSColor colorWithCalibratedRed:normal.bgRed green:normal.bgGreen
                                         blue:normal.bgBlue alpha:normal.bgAlpha];
    }
    if (normal.hasForeground) {
        fg = [NSColor colorWithCalibratedRed:normal.fgRed green:normal.fgGreen
                                        blue:normal.fgBlue alpha:normal.fgAlpha];
    }
    self.bgColor = bg;
    self.fgColor = fg;

    NSColor *selBg = selected.hasBackground
        ? [NSColor colorWithCalibratedRed:selected.bgRed green:selected.bgGreen
                                      blue:selected.bgBlue alpha:selected.bgAlpha]
        : [NSColor colorWithCalibratedWhite:0x88 / 255.0 alpha:1.0];
    NSColor *selFg = selected.hasForeground
        ? [NSColor colorWithCalibratedRed:selected.fgRed green:selected.fgGreen
                                     blue:selected.fgBlue alpha:selected.fgAlpha]
        : [NSColor colorWithCalibratedWhite:0xf6 / 255.0 alpha:1.0];
    self.selectedBgColor = selBg;
    self.selectedFgColor = selFg;

    if (_plateLayer) {
        _plateLayer.backgroundColor = bg.CGColor;
    }
    [self rebuildRows];
}

#pragma mark - Mouse

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    return hit;
}

// Click a row: select it and report through the same callback the keyboard
// path uses. GTK parity (completion.c on_selection_changed): every selection
// change rewrites the input line.
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger idx = floor(p.y / kRowHeight);
    if (idx < 0 || idx >= (NSInteger)self.candidates.count) { return; }
    self.highlightIndex = idx;
    [self repaintHighlight];
    if (self.onSelectionChanged) { self.onSelectionChanged(self.candidates[idx].value); }
}

@end

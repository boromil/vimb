// AppKit completion dropdown for vimb (parity with the GTK4 completion widget
// in src/completion.c). A native popover-style list rendered above the command
// field as the user types.
//
// Visuals follow the platform conventions used by native command palettes
// (Spotlight/Raycast-style): rounded corners, hairline border, soft drop
// shadow, full-row selection highlight (HIG "Focus and selection": lists use a
// row highlight, not a focus ring) and two-column rows — the candidate value
// plus a right-aligned dimmed detail column, mirroring GTK's CompletionItem
// first/second pair. Colors remain driven by the completion-css /
// completion-selected-css settings (GTK parity), defaulting to the classic
// #656565 box with white text.
//
// The candidate *generation / ranking / filtering* logic lives in the
// Foundation-only CompletionMatcher (CompletionCandidate.h) so that it is
// unit-testable; this view is AppKit-coupled and only ships with the app.
//
// Keyboard operation is exposed explicitly so the owning controller can route
// Tab/Shift-Tab/Enter/Esc: moveSelectionBy:+/- steps the highlight, the
// current row is read via `selectedValue`, and dismiss ends the session.
#import "CompletionDropdown.h"
#import "CompletionCandidate.h"

@interface CompletionDropdown () {
    NSTableColumn *_valueColumn;
}
@property (nonatomic, copy) NSArray<CompletionCandidate *> *candidates;
@property (nonatomic) NSInteger highlightIndex;
@property (nonatomic, strong) NSColor *fgColor;
@property (nonatomic, strong) NSColor *bgColor;
@property (nonatomic, strong) NSColor *selectedBgColor;
@property (nonatomic, strong) NSColor *selectedFgColor;
@end

// Row background painter: layer fills on cells never composited, so rows draw
// themselves (drawRect), honoring completion-css / completion-selected-css.
@interface CompletionRowView : NSTableRowView
@property (nonatomic, weak) CompletionDropdown *dropdown;
@end

@implementation CompletionRowView
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected = self.isSelected;
    NSColor *fill = selected ? self.dropdown.selectedBgColor : self.dropdown.bgColor;
    [fill setFill];
    NSRectFill(self.bounds);
}
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
        // The layer must NOT clip its children (masksToBounds would kill the
        // shadow) so the enclosed scroll view rounds + clips itself instead.
        self.layer.cornerRadius = kCornerRadius;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        self.layer.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.30].CGColor;
        self.layer.shadowOpacity = 1.0;
        self.layer.shadowRadius = 6.0;
        self.layer.shadowOffset = CGSizeMake(0.0, -2.0);
        self.candidates = @[];
        self.highlightIndex = -1;

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        scroll.hasVerticalScroller = YES;
        scroll.drawsBackground = NO;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scroll.wantsLayer = YES;
        scroll.layer.cornerRadius = kCornerRadius;
        scroll.layer.masksToBounds = YES;

        _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
        _tableView.headerView = nil;
        _tableView.rowHeight = kRowHeight;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.allowsEmptySelection = YES;
        _tableView.allowsMultipleSelection = NO;
        _tableView.backgroundColor = [NSColor clearColor];
        // Draw selection ourselves via the cell layers so the GTK
        // completion-selected-css colors (#888 bg, #f6f3e8 fg by default) are
        // honored; NSTableView's Regular style would paint the system accent
        // color instead (parity: src/setting.c SETTING_COMPLETION_SELECTED_CSS).
        _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;

        _valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
        _valueColumn.width = frame.size.width - 4;
        _valueColumn.resizingMask = NSTableColumnAutoresizingMask;
        [_tableView addTableColumn:_valueColumn];

        scroll.documentView = _tableView;
        [self addSubview:scroll];
        [self applyStyles];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    return [super initWithCoder:coder];
}

- (void)updateWithCandidates:(NSArray<CompletionCandidate *> *)candidates {
    self.candidates = candidates ?: @[];
    self.highlightIndex = -1;
    [_tableView reloadData];

    NSUInteger count = self.candidates.count;
    _tableView.enclosingScrollView.hidden = (count == 0);
    if (count == 0) { return; }
    CGFloat h = MIN((CGFloat)count * kRowHeight, kHardMaxHeight);
    NSRect f = self.frame;
    f.size.height = h;
    self.frame = f;
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
    CGFloat x = MAX(0, rect.origin.x);
    CGFloat w = MIN(rect.size.width, view.bounds.size.width - 2 * x);
    // The list grows up from the anchor, so it must also fit between the
    // anchor (plus the floating gap) and the top of the container.
    CGFloat avail = view.bounds.size.height - rect.origin.y - kAnchorGap;
    CGFloat h = MIN(MIN(MIN((CGFloat)count * kRowHeight, view.bounds.size.height / 3.0), kHardMaxHeight), avail);
    if (w < kRowHeight || h <= 0) { [self dismiss]; return; }
    self.frame = NSMakeRect(x, rect.origin.y + kAnchorGap, w, h);
    self.hidden = NO;
}

- (void)dismiss {
    self.hidden = YES;
    self.highlightIndex = -1;
    // Ending the session drops the candidates too, so `hasCandidates` reflects
    // "completion session active" (GTK FLAG_COMPLETION) rather than "rows were
    // shown at some point".
    self.candidates = @[];
    [_tableView deselectAll:nil];
    [_tableView reloadData];
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
    // Reload so the newly highlighted (and previously highlighted) rows
    // repaint their cell layers; with selectionHighlightStyle None the table
    // view itself would never redraw on a programmatic selectRowIndexes:.
    [_tableView reloadData];
    NSIndexSet *set = [NSIndexSet indexSetWithIndex:(NSUInteger)idx];
    [_tableView selectRowIndexes:set byExtendingSelection:NO];
    [_tableView scrollRowToVisible:(NSInteger)idx];
    return YES;
}

- (void)deselect {
    self.highlightIndex = -1;
    [_tableView deselectAll:nil];
    [_tableView reloadData];
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
    CompletionStyle *hover = [CompletionMatcher styleFromCSS:self.completionHoverCSS ?: @""];

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
    (void)hover;

    if (self.layer) {
        self.layer.backgroundColor = bg.CGColor;
    }
    [self setNeedsDisplay:YES];
    [_tableView reloadData];
}

// Paint the opaque plate in drawRect. Layer backgrounds proved unreliable
// here (the panel rendered as ghost text with the page showing through): the
// view sits inside a layer-backed scroll-view sandwich whose compositing
// dropped the panel and cell layer fills. drawRect is the dependable path;
// the layer keeps only border + shadow. GTK parity: the default plate is the
// #656565 #completion background (config.def.h SETTING_COMPLETION_CSS).
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *plate = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                          xRadius:kCornerRadius
                                                          yRadius:kCornerRadius];
    [self.bgColor setFill];
    [plate fill];
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.candidates.count;
}

- (id _Nullable)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.candidates.count) { return nil; }
    return self.candidates[row].value;
}

// Two-column row (GTK CompletionItem first/second): the candidate value on
// the left, an optional right-aligned dimmed detail on the right.
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    NSTextField *valueLabel = nil;
    NSTextField *detailLabel = nil;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, kRowHeight)];
        cell.identifier = @"cell";

        valueLabel = [[NSTextField alloc] init];
        valueLabel.identifier = @"value";
        valueLabel.editable = NO;
        valueLabel.selectable = NO;
        valueLabel.bezeled = NO;
        valueLabel.drawsBackground = NO;
        valueLabel.font = [NSFont systemFontOfSize:12.0];
        valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:valueLabel];

        detailLabel = [[NSTextField alloc] init];
        detailLabel.identifier = @"detail";
        detailLabel.editable = NO;
        detailLabel.selectable = NO;
        detailLabel.bezeled = NO;
        detailLabel.drawsBackground = NO;
        detailLabel.font = [NSFont systemFontOfSize:11.0];
        detailLabel.alignment = NSTextAlignmentRight;
        detailLabel.lineBreakMode = NSLineBreakByTruncatingHead;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:detailLabel];

        [NSLayoutConstraint activateConstraints:@[
            [valueLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [valueLabel.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [detailLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [detailLabel.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:valueLabel.trailingAnchor constant:8],
        ]];
    } else {
        for (NSView *sub in cell.subviews) {
            if (![sub isKindOfClass:[NSTextField class]]) { continue; }
            if ([sub.identifier isEqualToString:@"value"]) { valueLabel = (NSTextField *)sub; }
            if ([sub.identifier isEqualToString:@"detail"]) { detailLabel = (NSTextField *)sub; }
        }
    }
    if (row < 0 || row >= (NSInteger)self.candidates.count) { return cell; }
    CompletionCandidate *c = self.candidates[row];
    valueLabel.stringValue = c.value;
    BOOL selected = (row == self.highlightIndex);
    // Row backgrounds are drawn by CompletionRowView (see
    // tableView:rowViewForRow:); cell layer fills proved unreliable.
    valueLabel.textColor = selected ? (self.selectedFgColor ?: self.fgColor) : self.fgColor;
    if (c.detail.length > 0) {
        detailLabel.hidden = NO;
        detailLabel.stringValue = c.detail;
        detailLabel.textColor = [(selected ? (self.selectedFgColor ?: self.fgColor) : self.fgColor) colorWithAlphaComponent:0.65];
    } else {
        detailLabel.hidden = YES;
        detailLabel.stringValue = @"";
    }
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return YES;
}

// Full-row backgrounds (normal + selected) via a custom row view: layer
// fills on the cells never composited, so the rows draw themselves the way
// GTK's #completion > row{background-color:...} / :selected{...} CSS does.
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    CompletionRowView *rowView = [tableView makeViewWithIdentifier:@"vimbrow" owner:self];
    if (!rowView) {
        rowView = [[CompletionRowView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, kRowHeight)];
        rowView.identifier = @"vimbrow";
    }
    rowView.dropdown = self;
    return rowView;
}

// GTK parity (completion.c on_selection_changed): every selection change —
// keyboard stepping or a mouse click — reports the newly highlighted value so
// the owning controller can rewrite the input line (selfunc).
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.isHidden || self.candidates.count == 0) { return; }
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.candidates.count) { return; }
    self.highlightIndex = row;
    if (self.onSelectionChanged) { self.onSelectionChanged(self.candidates[row].value); }
}

@end

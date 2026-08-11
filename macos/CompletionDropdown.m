// AppKit completion dropdown (parity with src/completion.c). Renders an
// opaque, frame-free list of CompletionCandidates below a command field and
// exposes keyboard navigation (moveSelectionBy:), selection (selectedValue)
// and dismissal (dismiss). Styling is lifted from the registered completion-*
// CSS settings via CompletionStyleParser (Foundation-only).
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

@implementation CompletionDropdown

static const CGFloat kRowHeight = 20.0;
static const CGFloat kMaxHeight = 240.0;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 4.0;
        self.candidates = @[];
        self.highlightIndex = -1;

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        scroll.hasVerticalScroller = YES;
        scroll.drawsBackground = NO;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
        _tableView.headerView = nil;
        _tableView.rowHeight = kRowHeight;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.allowsEmptySelection = YES;
        _tableView.allowsMultipleSelection = NO;
        _tableView.backgroundColor = [NSColor clearColor];
        _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

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
    CGFloat h = MIN((CGFloat)count * kRowHeight, kMaxHeight);
    NSRect f = self.frame;
    f.size.height = h;
    self.frame = f;
}

- (void)presentRelativeToRect:(NSRect)rect inView:(NSView *)view {
    NSUInteger count = self.candidates.count;
    if (count == 0) { [self dismiss]; return; }
    CGFloat h = MIN((CGFloat)count * kRowHeight, kMaxHeight);
    CGFloat yInSuper = rect.origin.y - h;
    NSRect f = NSMakeRect(rect.origin.x, yInSuper, rect.size.width, h);
    self.frame = f;
    self.hidden = NO;
}

- (void)dismiss {
    self.hidden = YES;
    self.highlightIndex = -1;
}

- (BOOL)hasCandidates {
    return self.candidates.count > 0;
}

- (BOOL)moveSelectionBy:(NSInteger)direction {
    NSUInteger count = self.candidates.count;
    if (!self.isHidden && count == 0) { return NO; }
    if (count == 0) { return NO; }
    NSInteger idx = self.highlightIndex;
    if (idx == -1) {
        idx = (direction >= 0) ? 0 : (NSInteger)count - 1;
    } else {
        idx += direction;
        if (idx < 0) { idx = (NSInteger)count - 1; }
        if (idx >= (NSInteger)count) { idx = 0; }
    }
    self.highlightIndex = idx;
    NSIndexSet *set = [NSIndexSet indexSetWithIndex:(NSUInteger)idx];
    [_tableView selectRowIndexes:set byExtendingSelection:NO];
    [_tableView scrollRowToVisible:(NSInteger)idx];
    return YES;
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
    // #completion row color:#fff on background:#656565.
    NSColor *bg = [NSColor colorWithCalibratedRed:0.40 green:0.40 blue:0.40 alpha:1.0];
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
        : [NSColor selectedControlColor];
    NSColor *selFg = selected.hasForeground
        ? [NSColor colorWithCalibratedRed:selected.fgRed green:selected.fgGreen
                                      blue:selected.fgBlue alpha:selected.fgAlpha]
        : fg;
    self.selectedBgColor = selBg;
    self.selectedFgColor = selFg;
    (void)hover;

    if (self.layer) {
        self.layer.backgroundColor = bg.CGColor;
    }
    [_tableView reloadData];
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

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, kRowHeight)];
        cell.identifier = @"cell";
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(3, 2, tableColumn.width - 6, kRowHeight - 4)];
        label.identifier = @"text";
        label.editable = NO;
        label.selectable = NO;
        label.bezeled = NO;
        label.drawsBackground = NO;
        label.font = [NSFont systemFontOfSize:12.0];
        [cell addSubview:label];
    }
    if (row < 0 || row >= (NSInteger)self.candidates.count) { return cell; }
    CompletionCandidate *c = self.candidates[row];
    NSTextField *tf = nil;
    for (NSView *sub in cell.subviews) {
        if ([sub isKindOfClass:[NSTextField class]]) { tf = (NSTextField *)sub; break; }
    }
    tf.stringValue = c.value;
    if (row == self.highlightIndex) {
        cell.wantsLayer = YES;
        cell.layer.backgroundColor = self.selectedBgColor.CGColor;
        tf.textColor = (self.selectedFgColor ?: self.fgColor);
    } else {
        cell.wantsLayer = YES;
        cell.layer.backgroundColor = self.bgColor.CGColor;
        tf.textColor = self.fgColor;
    }
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return YES;
}

@end

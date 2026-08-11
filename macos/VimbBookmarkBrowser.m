#import "VimbBookmarkBrowser.h"
#import "VimbBookmarkStore.h"
#import "VimbStorage.h"

// A table that interprets the bookmark-browser keys: Return opens the selected
// bookmark, 'd' deletes it, Esc closes the panel.
@interface VimbBookmarkTableView : NSTableView
@property(nonatomic, weak) VimbBookmarkBrowser *browser;
@end

@interface VimbBookmarkBrowser ()
@property(nonatomic, strong) VimbBookmarkStore *store;
@property(nonatomic, strong) NSSearchField *filterField;
@property(nonatomic, strong) VimbBookmarkTableView *tableView;
@property(nonatomic, strong) NSArray<VimbBookmark *> *results;
@end

// NSSearchField delegate (inherits NSTextFieldDelegate) routes to this browser;
// conforming here silences the incompatible-delegate-type warning.
@interface VimbBookmarkBrowser () <NSSearchFieldDelegate>
@end

@implementation VimbBookmarkBrowser

+ (instancetype)sharedBrowser {
    static VimbBookmarkBrowser *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Back the browser with the same bookmarks file :bma/:bmr use.
        NSString *path = [[VimbStorage appSupportDir] stringByAppendingPathComponent:@"bookmark"];
        instance = [[VimbBookmarkBrowser alloc] initWithStore:[[VimbBookmarkStore alloc] initWithPath:path]];
    });
    return instance;
}

- (instancetype)initWithStore:(VimbBookmarkStore *)store {
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = @"Bookmarks";
    panel.level = NSFloatingWindowLevel;
    self = [super initWithWindow:panel];
    if (self) {
        _store = store;
        _results = @[];
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    _filterField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _filterField.placeholderString = @"Filter bookmarks (tags / title / URL)";
    _filterField.delegate = self;
    _filterField.translatesAutoresizingMaskIntoConstraints = NO;
    _filterField.action = @selector(filterFieldChanged:);
    _filterField.target = self;

    // Single column: "title  ·  URL", with the URL as a secondary line.
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;

    _tableView = [[VimbBookmarkTableView alloc] initWithFrame:NSZeroRect];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.allowsMultipleSelection = NO;
    _tableView.browser = self;
    NSTableColumn *bmCol = [[NSTableColumn alloc] initWithIdentifier:@"bookmark"];
    bmCol.title = @"Bookmarks";
    bmCol.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:bmCol];
    [_tableView reloadData];
    scroll.documentView = _tableView;

    NSStackView *stack = [NSStackView stackViewWithViews:@[_filterField, scroll]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10],
        [_filterField.heightAnchor constraintEqualToConstant:24],
    ]];

    [self reloadResults];
}

- (IBAction)showBookmarks:(id)sender {
    (void)sender;
    [self presentBookmarks];
}

- (void)presentBookmarks {
    [self reloadResults];
    if (!self.window.isVisible) {
        [NSApp runModalForWindow:self.window];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)reloadResults {
    self.results = [self.store bookmarksMatching:self.filterField.stringValue];
    [self.tableView reloadData];
    if (self.results.count) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (void)filterFieldChanged:(id)sender {
    (void)sender;
    [self reloadResults];
}

// NSTextFieldDelegate: filter as you type.
- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.filterField) {
        [self reloadResults];
    }
}

#pragma mark - Actions

- (void)openSelectedBookmark {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.results.count) { row = 0; }
    if (row < 0 || (NSUInteger)row >= self.results.count) { return; }
    NSString *url = self.results[row].url;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VimbRunCommand"
        object:nil userInfo:@{ @"command": [NSString stringWithFormat:@"open %@", url] }];
    [self closePanel];
}

- (void)deleteBookmarkAtRow:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.results.count) { return; }
    VimbBookmark *bm = self.results[row];
    [self.store removeBookmarkForURL:bm.url];
    // Retain a sensible selection around the deleted row.
    NSInteger next = MIN(row, (NSInteger)self.results.count - 2);
    [self reloadResults];
    if (self.results.count && next >= 0 && next < (NSInteger)self.results.count) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
    }
}

- (void)closePanel {
    if ([NSApp modalWindow] == self.window) {
        [NSApp stopModalWithCode:0];
    }
    [self.window orderOut:nil];
}

#pragma mark - NSTableView data source / delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.results.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    (void)tableColumn;
    VimbBookmarkTableView *tv = (VimbBookmarkTableView *)tableView;
    NSTableCellView *cell = [tv makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        NSTextField *text = [NSTextField labelWithString:@""];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:text];
        cell.textField = text;
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [text.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-2],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        cell.identifier = @"cell";
    }
    if (row < (NSInteger)self.results.count) {
        VimbBookmark *bm = self.results[row];
        cell.textField.stringValue = bm.title.length ? bm.title : bm.url;
        if (bm.title.length) {
            cell.textField.toolTip = bm.url;
            cell.toolTip = bm.url;
        }
    }
    return cell;
}

@end

@implementation VimbBookmarkTableView

- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    unichar c = chars.length ? [chars characterAtIndex:0] : 0;
    if (c == '\r' || c == '\n') {           // Return / Enter -> open
        [self.browser openSelectedBookmark];
        return;
    }
    if (c == 27) {                          // Esc -> close
        [self.browser closePanel];
        return;
    }
    if ((c == 'd' || c == 'D') && (event.modifierFlags & NSEventModifierFlagCommand) == 0) {
        [self.browser deleteBookmarkAtRow:self.selectedRow];
        return;
    }
    [super keyDown:event];
}

- (BOOL)acceptsFirstResponder { return YES; }

@end

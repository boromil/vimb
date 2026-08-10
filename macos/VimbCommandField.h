#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Command-line field that intercepts vimb ex-keypress editing combos
// (Ctrl-P/N history, Ctrl-C cancel, Ctrl-W delete word, Ctrl-[ cancel) which
// AppKit doesn't synthesize as editable-text selectors.
@class VimbCommandField;
@protocol VimbCommandFieldDelegate <NSTextFieldDelegate>
- (void)commandField:(VimbCommandField *)field requestedHistory:(NSInteger)direction; // -1 prev, +1 next
- (void)commandFieldRequestedCancel:(VimbCommandField *)field;
- (void)commandFieldDeleteWord:(VimbCommandField *)field;
@end

@interface VimbCommandField : NSTextField
@property(nonatomic, weak, nullable) id<VimbCommandFieldDelegate> vbDelegate;
@end

NS_ASSUME_NONNULL_END

#import "VimbWindow.h"
#import "BrowserWindowController.h"

@implementation VimbWindow

// Guarantee the browser key equivalents (Cmd-T new tab, Cmd-W close tab)
// are handled regardless of the current first responder or menu key-
// equivalent dispatch, falling back to super (the menu) when not handled.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0) {
        NSString *chars = event.charactersIgnoringModifiers;
        if (chars.length == 1) {
            unichar c = [chars characterAtIndex:0];
            BrowserWindowController *wc = (BrowserWindowController *)self.windowController;
            if (![wc isKindOfClass:[BrowserWindowController class]]) {
                return [super performKeyEquivalent:event];
            }
            if (c == 't') {
                [wc openNewTab];
                return YES;
            }
            if (c == 'w') {
                [wc closeActiveTab];
                return YES;
            }
        }
    }
    return [super performKeyEquivalent:event];
}

@end

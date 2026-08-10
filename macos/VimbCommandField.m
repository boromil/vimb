#import "VimbCommandField.h"

@implementation VimbCommandField

- (BOOL)isOpaque { return NO; }

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags mods = event.modifierFlags;
    BOOL ctrl = (mods & NSEventModifierFlagControl) != 0;
    NSString *chars = event.charactersIgnoringModifiers;
    if (ctrl && chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c == '[') {
            if (self.vbDelegate) [self.vbDelegate commandFieldRequestedCancel:self];
            return;
        }
        if (c == 'c') {
            if (self.vbDelegate) [self.vbDelegate commandFieldRequestedCancel:self];
            return;
        }
        if (c == 'p') {
            if (self.vbDelegate) [self.vbDelegate commandField:self requestedHistory:-1];
            return;
        }
        if (c == 'n') {
            if (self.vbDelegate) [self.vbDelegate commandField:self requestedHistory:1];
            return;
        }
        if (c == 'w') {
            if (self.vbDelegate) [self.vbDelegate commandFieldDeleteWord:self];
            return;
        }
        // Command-line cursor/editing keys (ex_keypress parity).
        if (c == 'b') { // Ctrl-B: cursor to beginning
            NSText *ed = self.currentEditor;
            if (ed) { [ed setSelectedRange:NSMakeRange(0, 0)]; }
            return;
        }
        if (c == 'e') { // Ctrl-E: cursor to end
            NSText *ed = self.currentEditor;
            if (ed) { [ed setSelectedRange:NSMakeRange(ed.string.length, 0)]; }
            return;
        }
        if (c == 'u') { // Ctrl-U: delete everything before the cursor
            NSText *ed = self.currentEditor;
            if (ed && ed.selectedRange.location != NSNotFound) {
                NSUInteger loc = ed.selectedRange.location;
                [ed replaceCharactersInRange:NSMakeRange(0, loc) withString:@""];
            }
            return;
        }
    }
    [super keyDown:event];
}

@end

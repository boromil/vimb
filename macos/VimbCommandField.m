#import "VimbCommandField.h"

@implementation VimbCommandField {
    BOOL _registerMode;
}

- (BOOL)isOpaque { return NO; }

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags mods = event.modifierFlags;
    BOOL ctrl = (mods & NSEventModifierFlagControl) != 0;
    NSString *chars = event.charactersIgnoringModifiers;

    // Ctrl-R register-insert mode: the next printable key names a register
    // whose content is inserted at the cursor (ex_keypress PHASE_REG).
    if (_registerMode) {
        _registerMode = NO;
        if (chars.length == 1) {
            unichar k = [chars characterAtIndex:0];
            NSString *content = [self.vbDelegate commandField:self registerContentForKey:k];
            if (content) {
                NSText *ed = self.currentEditor;
                if (ed) { [ed replaceCharactersInRange:ed.selectedRange withString:content]; }
            }
        }
        return;
    }

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
        if (c == 'r') {
            _registerMode = YES;
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
    // Arrow Up/Down: command-line history (GTK main.c maps GDK_KEY_Up/Down to
    // ex_keypress KEY_UP/KEY_DOWN -> history()). The plain field would move a
    // caret that doesn't exist in vimb's single-line prompt.
    if (chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c == NSUpArrowFunctionKey) {
            if (self.vbDelegate) [self.vbDelegate commandField:self requestedHistory:-1];
            return;
        }
        if (c == NSDownArrowFunctionKey) {
            if (self.vbDelegate) [self.vbDelegate commandField:self requestedHistory:1];
            return;
        }
    }
    [super keyDown:event];
}

@end

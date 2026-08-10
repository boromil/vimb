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
    }
    [super keyDown:event];
}

@end

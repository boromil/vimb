#import "VimbHintEngine.h"

// FEATURE_QUEUE is enabled in src/config.def.h, so the hint modes include the
// queue modes p/P and the g-modes list includes IopPstyY.
static NSString *const kModes       = @"eiIkoOpPstTxyY";
static NSString *const kGModes      = @"IopPstyY";

static BOOL chIn(NSString *str, unichar c) {
    return [str rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound;
}

@implementation VimbHintEngine

+ (BOOL)parseMode:(NSString *)prompt mode:(unichar *)outMode isGmode:(BOOL *)outIsGmode {
    if (prompt.length == 0) {
        return NO;
    }
    unichar pmode = 0;
    BOOL isGmode  = NO;
    unichar p0 = [prompt characterAtIndex:0];

    if (p0 == ';') {
        if (prompt.length < 2) { return NO; }
        pmode = [prompt characterAtIndex:1];
        isGmode = NO;
    } else if (p0 == 'g' && prompt.length >= 3) {
        // "g;X" g-mode hinting uses the third char as the mode.
        pmode = [prompt characterAtIndex:2];
        isGmode = YES;
    } else {
        return NO;
    }

    BOOL valid = (isGmode ? chIn(kGModes, pmode) : chIn(kModes, pmode));
    if (!valid) { return NO; }

    if (outMode)    { *outMode = pmode; }
    if (outIsGmode) { *outIsGmode = isGmode; }
    return YES;
}

+ (BOOL)validMode:(unichar)mode gmode:(BOOL)gmode {
    return gmode ? chIn(kGModes, mode) : chIn(kModes, mode);
}

+ (VimbHintAction)actionForMode:(unichar)mode {
    if (mode == 'k') { return VimbHintActionRemove; }
    if (mode == 'o' || mode == 't') { return VimbHintActionOpen; }
    if (mode == 'Y') { return VimbHintActionYankText; }
    // e i I O p P s T x y -> DATA group.
    if (chIn(@"eiIOpPsTxy", mode)) { return VimbHintActionData; }
    return VimbHintActionNone;
}

+ (BOOL)handlesFormForMode:(unichar)mode {
    return chIn(@"eot", mode);
}

+ (BOOL)isDataMode:(unichar)mode {
    return chIn(@"eiIOpPsTxy", mode);
}

+ (VimbHintDispatch)dispatchForDataMode:(unichar)mode {
    switch (mode) {
        case 'i': case 'I': return VimbHintDispatchOpen;
        case 'O': case 'T': return VimbHintDispatchCommandOpen;
        case 's':           return VimbHintDispatchSave;
        case 'x':           return VimbHintDispatchXHint;
        case 'y': case 'Y': return VimbHintDispatchYank;
        case 'p': case 'P': return VimbHintDispatchQueue;
        case 'k':           return VimbHintDispatchRemove;
        case 'e':           return VimbHintDispatchInsert;
        default:            return VimbHintDispatchNone;
    }
}

+ (BOOL)opensNewTab:(unichar)mode {
    return (mode == 'I' || mode == 't');
}

+ (NSString *)commandLinePrefixForMode:(unichar)mode {
    return (mode == 'T') ? @":tabopen " : @":open ";
}

@end

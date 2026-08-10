#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Faithful port of the hint-mode semantics found in src/hints.c
// (hints_parse_prompt and the DATA:<value> switch in hint_function_check_result)
// and the xpath/action tables in src/scripts/hints.js, extracted as a pure,
// Foundation-only helper so it can be unit-tested without a WKWebView. The
// exact JS lives in KeyboardWebView.m; this class only answers the "which
// element set / which action / what to dispatch" questions the JS and the
// native controller both need.

// The mode's element-collection + action category (mirrors hints.js actionmap).
typedef NS_ENUM(NSInteger, VimbHintAction) {
    VimbHintActionNone = 0,
    VimbHintActionOpen,      // o/t: click-open the element -> DONE
    VimbHintActionData,      // e i I O p P s T x y: report DATA with getSrc value
    VimbHintActionRemove,    // k: remove the element -> DONE
    VimbHintActionYankText,  // Y: report DATA with element textContent
};

// The native dispatch decided for a "DATA:" result (mirrors the switch in
// hint_function_check_result, with queue support since FEATURE_QUEUE is on).
typedef NS_ENUM(NSInteger, VimbHintDispatch) {
    VimbHintDispatchNone = 0,
    VimbHintDispatchOpen,        // i/I: open the image value (current / new tab)
    VimbHintDispatchCommandOpen, // O/T: prefill the command line
    VimbHintDispatchSave,        // s: save the value URI
    VimbHintDispatchXHint,       // x: run the x-hint-command with the value
    VimbHintDispatchYank,        // y/Y: yank the value to ';' then current reg
    VimbHintDispatchQueue,       // p/P: push/unshift the value onto the queue
    VimbHintDispatchRemove,      // k: element already removed, nothing more
    VimbHintDispatchInsert,      // e with INSERT: form field was focused
};

@interface VimbHintEngine : NSObject

// Mirrors hints_parse_prompt: accepts ";X" (normal mode) or "g;X" (g-mode) and,
// when the named mode is valid for that scope, fills *outMode and *outIsGmode
// and returns YES.
+ (BOOL)parseMode:(nullable NSString *)prompt
             mode:(nullable unichar *)outMode
          isGmode:(nullable BOOL *)outIsGmode;

// Whether `mode` is a valid hint mode for normal (gmode=NO) or g-mode
// (gmode=YES) hinting. Mirrors the "modes"/"g_modes" strings in hints.c (with
// FEATURE_QUEUE enabled).
+ (BOOL)validMode:(unichar)mode gmode:(BOOL)gmode;

// The action category for the mode (port of hints.js actionmap).
+ (VimbHintAction)actionForMode:(unichar)mode;
// Whether the mode's element set includes form fields that should be handled
// (focused/toggled) by the script (e/o/t in hints.js).
+ (BOOL)handlesFormForMode:(unichar)mode;
// YES when the mode belongs to the "DATA" group that posts the element
// src/href back to native (e i I O p P s T x y).
+ (BOOL)isDataMode:(unichar)mode;

// Port of the DATA:<value> dispatch switch in hint_function_check_result.
+ (VimbHintDispatch)dispatchForDataMode:(unichar)mode;
// YES when the mode opens into a feature window via the native layer (i.e. the
// new-tab modes: 't' (native new tab) and 'I' (image in new tab)). 'T' opens a
// new-tab command-line prompt (VimbHintDispatchCommandOpen) rather than a URL.
+ (BOOL)opensNewTab:(unichar)mode;
// The command-line prefix echoed for O/T modes (":open "/":tabopen ").
+ (NSString *)commandLinePrefixForMode:(unichar)mode;

@end

NS_ASSUME_NONNULL_END

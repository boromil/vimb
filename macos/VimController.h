#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VimMode) {
    VimModeNormal,
    VimModeCommand,   // ':'/'/'/'?' lead-in editing (vim prompt)
    VimModeSearch,    // search prompt
    VimModeHint,      // hint overlay active
    VimModePassThrough // ^Z: all keys to the page except ESC
};

// Delegate implemented by the UI (BrowserWindowController). Keeps the vim
// state machine independent of AppKit/WKWebView. Mirrors the actions invoked
// by vimb's normal.c command handlers.
@protocol VimDelegate <NSObject>
// Scroll: pass the actual mode character and count, as vimb's normal_scroll
// forwards 'j','k','$','0','G','g',^D,^U,^F,^B to vbscroll().
- (void)vimScrollMode:(unichar)mode count:(NSUInteger)count;
- (void)vimGoBack;
- (void)vimGoForward;
- (void)vimReload;
- (void)vimStop;
- (void)vimOpenURL:(nullable NSString *)urlValue inNewTab:(BOOL)newTab;
- (void)vimOpenHome;                       // 'U'/'u' reopen last closed page
- (void)vimGoHomeURL;                      // 'gu'/'gU' go up one path segment
- (void)vimOpenPrompt:(NSString *)prompt mode:(VimMode)mode;   // handle ':' / '/' / '?' / "o"/"t" opens
- (void)vimSearch:(NSString *)query forward:(BOOL)forward;
- (void)vimSearchDirection:(NSInteger)dir; // n/N with count
- (void)vimSearchSelectionForward:(BOOL)forward;
- (void)vimFire;                            // ^M: click link at search highlight
- (void)vimFocusLastActive;                 // 'i'
- (void)vimFocusInput;                      // 'g i'
- (void)vimNextTab;
- (void)vimPrevTab;
- (void)vimGotoTab:(NSUInteger)index;       // g0, g$
- (void)vimGotoTabFromLast:(NSInteger)count; // NgT (count from last)
- (void)vimNewTab;
- (void)vimCloseTab;
- (void)vimToggleHints;
- (void)vimEnterHints:(NSString *)mode gmode:(BOOL)gmode;   // mode: full hint mode char, gmode keeps open
- (void)vimHintKey:(NSString *)key;
- (void)vimHintFocus:(BOOL)back;             // Tab / Shift-Tab in hint mode
- (void)vimHintBackspace;
- (void)vimHintFire;                         // Enter in hint mode
- (void)vimShowMessage:(NSString *)message error:(BOOL)error;
- (void)vimFocusWebView;
- (void)vimEnterPassThrough;                // ^Z
- (void)vimYankURI;                         // y
- (void)vimYankSelection;                   // Y: yank page selection
- (void)vimSetMark:(unichar)c;              // m<char>
- (void)vimJumpMark:(unichar)c;             // '<char>
- (void)vimViewSource;                      // gf/gF
- (void)vimZoom:(BOOL)in;
- (void)vimIncrement:(BOOL)up count:(NSInteger)count;  // ^A / ^X
- (void)vimQuit;                            // ^Q
- (void)vimOpenClipboard:(NSString *)counter; // p/P paste register
@end

@interface VimController : NSObject
@property(nonatomic, assign) VimMode mode;
// One-shot normal mode from a page text field (Ctrl-O in input, port of
// input.c input_keypress): the next keys run as normal-mode commands.
@property(nonatomic, assign) BOOL oneShotNormal;
@property(nonatomic, weak, nullable) id<VimDelegate> delegate;
- (void)reset;
// Whether a key should be handed to the page (true) vs processed by vim mode
// (false), given whether a page text field currently holds focus. Mirrors
// vimb's normal-vs-input mode split.
- (BOOL)shouldPassKeysToPage:(BOOL)pageEditableActive;
// Handle a key while a page text field is focused (input mode). Returns YES
// if the key was consumed (e.g. Ctrl-O one-shot normal, ESC). Port of
// input.c input_keypress.
- (BOOL)handlePageEditableKeyCode:(int)keyCode
                        modifiers:(unsigned long)mods
                       characters:(NSString *)charsIgnoring;
// Returns YES if the key was consumed by vim mode.
- (BOOL)handleKeyDown:(NSEvent *)event inWebView:(BOOL)inWebView;
// Foundation-only core of handleKeyDown:. The UI extracts the event's
// keyCode, modifierFlags and charactersIgnoringModifiers and forwards them
// here so the engine can be unit-tested without AppKit. The `mods` argument
// takes the NSEventModifierFlags bitmask as an unsigned long; only the
// Control and Command bits are inspected.
- (BOOL)handleKeyCode:(int)keyCode
            modifiers:(unsigned long)mods
        characters:(NSString *)charsIgnoring;
// Called when the user finishes typing a prompt line / hint selection.
- (void)commandLineCommitted:(NSString *)line;
- (void)commandLineCancelled;
@end

NS_ASSUME_NONNULL_END

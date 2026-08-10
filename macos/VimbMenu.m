#import "VimbMenu.h"

@implementation VimbMenu

+ (NSMenu *)mainMenu {
    // --- Apple menu ---
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"vimb"];
    [appMenu addItemWithTitle:@"About vimb" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit vimb" action:@selector(terminate:) keyEquivalent:@"q"];

    // --- File menu ---
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
    [fileMenu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"W"];

    // --- Edit menu (standard; actions route to the focused field / web view) ---
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    // --- View menu ---
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
    [viewMenu addItemWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
    [viewMenu addItemWithTitle:@"Reload Page" action:@selector(reloadPage:) keyEquivalent:@"r"];
    [viewMenu addItemWithTitle:@"Stop Loading" action:@selector(stopLoading:) keyEquivalent:@"."];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];

    // --- Window menu ---
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"W"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItemWithTitle:@"Toggle Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];

    NSMenuItem *appRoot = [[NSMenuItem alloc] initWithTitle:@"vimb" action:nil keyEquivalent:@""];
    appRoot.submenu = appMenu;
    NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    fileRoot.submenu = fileMenu;
    NSMenuItem *editRoot = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    editRoot.submenu = editMenu;
    NSMenuItem *viewRoot = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    viewRoot.submenu = viewMenu;
    NSMenuItem *windowRoot = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    windowRoot.submenu = windowMenu;

    NSMenu *main = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    [main addItem:appRoot];
    [main addItem:fileRoot];
    [main addItem:editRoot];
    [main addItem:viewRoot];
    [main addItem:windowRoot];

    NSApplication *app = [NSApplication sharedApplication];
    app.windowsMenu = windowMenu;
    return main;
}

@end

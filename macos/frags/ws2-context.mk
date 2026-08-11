# WS-2 context-menu (see ../PARALLEL-SUBAGENTS.md).
# App target sources (Obj-C files compiled into vimb.app).
STREAM_SRCS += VimbContextMenu.m

# Test-target sources (Foundation-only). The menu-TREE builder in VimbContextMenu
# avoids AppKit (it emits plain NSDictionary descriptors); the AppKit NSMenu
# construction lives in KeyboardWebView, which is NOT in the test target.
STREAM_TEST_SRCS += VimbContextMenu.m

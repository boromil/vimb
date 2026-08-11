# WS-4 Bookmarks browser UI  (see ../PARALLEL-SUBAGENTS.md)
# App target sources: Foundation store + AppKit browser compiled into vimb.app.
STREAM_SRCS += VimbBookmarkStore.m
STREAM_SRCS += VimbBookmarkBrowser.m

# Test-target sources: only the Foundation-only store is unit-tested.
STREAM_TEST_SRCS += VimbBookmarkStore.m

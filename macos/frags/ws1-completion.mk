# WS-1 Completion dropdown (see ../PARALLEL-SUBAGENTS.md). Port of
# src/completion.c + util.c util_fill_completion / setting.c
# setting_fill_completion.
#
# App target sources (Obj-C files compiled into vimb.app):
#  - CompletionDropdown.m is AppKit-coupled (the native dropdown view).
# App + test-target sources (Foundation-only classes actually unit tested):
#  - CompletionCandidate.m is AppKit-free (candidate model + matcher + style
#    parser) so it can be compiled/linked into the Foundation-only test bin.
STREAM_SRCS       += CompletionDropdown.m CompletionCandidate.m
STREAM_TEST_SRCS  += CompletionCandidate.m

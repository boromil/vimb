# Per-workstream Makefile fragments

Each claimed workstream (see ../PARALLEL-SUBAGENTS.md) adds ONE `.mk` file here
so its new source files reach both build targets WITHOUT racing the shared
`Makefile`. The main Makefile auto-includes `frags/*.mk`.

Pattern for `frags/<stream>.mk`:

```make
# WS-<N> <stream-name>  (see ../PARALLEL-SUBAGENTS.md)
# App target sources (Obj-C files compiled into vimb.app)
STREAM_SRCS += MyFile.m

# Test-target sources (Foundation-only classes you actually unit test).
# AppKit/WKWebView-coupled files must NOT be added here, only to STREAM_SRCS.
STREAM_TEST_SRCS += MyFile.m
```

Rules:
- Append (`+=`), never `:=` — you are merging into the aggregated lists.
- New `.m` files must be under `../macos/` (sibling of this dir).
- Optional `.h` files need no Makefile entry (picked up via #import).
- A stream that touches no new files (polish-only) may omit `frags/<stream>.mk`
  entirely and just edit its owned existing files.
- The lead adds the fragment serially; ordering across fragments does not matter.

Verification after adding a fragment:
```
make -C macos test      # zero failures
make -C macos           # clean, 0 warnings, app links
```

# Parallel sub-agent workstreams (vimb macOS port)

This file lets several sub-agents port the remaining vimb→macOS gaps **in
parallel** without stepping on each other. Read it before starting any task.
Every workstream below owns a **disjoint** set of files, so concurrent agents
cannot collide — **as long as you never edit a file outside your owned set.**

---

## Golden contract (every workstream, every commit)

1. **Parity first.** Compare against the GTK4 original in `src/`. Verify
   behavior matches; fix divergences, don't paper over them. Cite the `src/*.c`
   function you are porting in your commit message.
2. **TDD.** Write failing tests first: add a `static void test_*()` in
   `macos/tests/test_behavior.m`, register it in `run_behavior_main()`, and
   add your source to the test target. Then `make -C macos test` (custom
   harness + llvm-cov, no XCTest). Zero failures required. Cover Foundation-only
   classes; AppKit/WKWebView-coupled code (BrowserWindowController,
   KeyboardWebView, windows) is NOT in the test target.
3. **Build.** `make -C macos` clean, 0 warnings.
4. **Commit + push** in short lowercase imperative style after each working
   increment. Keep `HEAD == origin/master`. `origin` = fork (push here).
   `upstream` = original fanglingsu/vimb (never push).
5. **Update `PARALLEL-SUBAGENTS.md`**: flip your row's status to `[done]` and
   add a one-line note. Do not touch other rows.
6. **Record learnings** in the memory tool under your task tag (see each
   workstream). Add a `gaps`-tagged note if you discover a new non-portable item.

---

## Ground rules to avoid collisions

- **Your owned set = only the files listed in your "Owns" section.** Never edit
  the Makefile's shared top block, `tests/test_behavior.m`'s existing tests, or
  a source file owned by another workstream.
- **Adding new source files:** append your `.m`/`.h` to the Makefile in the two
  EXACT spots each workstream lists (`SRCS` block and `TEST_SRCS` block). If two
  streams add files to the same Makefile simultaneously you will conflict —
  so the workbook below sequences additions OR uses a small per-stream makefile
  fragment. Prefer the fragment pattern (see below).
- **Reducing test-file contention:** each workstream gets ONE new test function
  registered at a single designated append point. Coordinate registration
  through the workbook's claim order so two streams never append the same line
  range at once.
- **A shared file is only "owned" by the stream listed below; others may append
  but never modify existing lines.** If you must change shared logic, pull it
  out into your own file instead.

### Preferred pattern: per-stream makefile fragment (avoids SRCS race)

Add `include frags/<stream>.mk` to the main Makefile once (the sequencer does
this serially), then each stream's `frags/<stream>.mk` defines:

```
STREAM_SRCS   := MyFile.m MyOtherFile.m
STREAM_TESTS  += MyFile.m MyOtherFile.m
```

and `STREAM_TESTS` feeds both the app SRCS and the test target (see example
include in the Makefile). This keeps parallel file additions from racing on the
same Makefile lines.

---

## Workstreams (current)

Legend: `[open]` = claimable, `[claimed]` = in progress by an agent, `[done]` =
merged, `[blocked]` = cannot proceed (dependency), `[n/a]` = not portable /
WKWebView ceiling.

### WS-1  Completion dropdown (`completion.c` parity) — `[done]`
- **Goal:** replace the current tab-cycle completion in `BrowserWindowController`
  with a native dropdown that lists candidates (URLs, commands, settings,
  hints) as the user types, using the existing `completion-cycle` candidates.
  Keyboard-only navigation (Tab/Shift-Tab/Enter/Esc), opaque (not glass),
  styled from the registered `completion-*` CSS settings.
- **Owns:** `macos/CompletionDropdown.h`, `macos/CompletionDropdown.m`,
  `frags/ws1-completion.mk`, `macos/tests/test_behavior.m` (your single new test
  fn `test_completion_dropdown`), `docs/README.md` (only if adding build note).
- **Reference:** `src/completion.c` + `src/scripts/dom_operations.js`.
- **Memory tag:** `completion`.
- **Build note:** dropdown view is AppKit-coupled → NOT in test target; keep the
  candidate-generation logic (score/rank/filter) in a Foundation-only class you
  DO test.
- **Done:** added `CompletionCandidate.h/m` (Foundation-only candidate + prefix/
  substring matcher + GTK `completion-*` CSS parser) in the test target, and the
  opaque `CompletionDropdown.h/m` view (NSTableView) fed by the matcher; keyboard
  Tab/Shift-Tab/Enter/Esc exposed via moveSelectionBy:/selectedValue/dismiss.
  Full wiring into BrowserWindowController's command field was deferred — that
  file is owned by another workstream (see summary).

### WS-2  Context menu (`context-menu.c` parity) — `[done]`
- **Goal:** wire `NSMenu` on right-click in `KeyboardWebView` so the vimb
  browser actions (back/forward/reload, copy-link/URL, open-in-tab/window, hint
  shortcuts) are reachable via right-click, matching what `context-menu.c`
  builds. Keep keyboard-first: every item must also be in the menu bar.
- **Owns:** `macos/VimbContextMenu.h`, `macos/VimbContextMenu.m`,
  `frags/ws2-context.mk`, `macos/KeyboardWebView.m` (your handler methods only),
  `macos/tests/test_behavior.m` (your single new test fn
  `test_context_menu_build` for the menu-tree builder, which stays Foundation/AppKit-menu-only if possible).
- **Gotcha:** WKWebView intercepts context presses; you'll need to decide between
  `WKWebView` `menuItemsForElement:` (private-looking) or overriding
  `menu(for:)`/`rightMouseDown:` on the super — document which works on this SDK.
- **Reference:** `src/context-menu.c`.
- **Memory tag:** `context_menu`.
- **Done:** overrode `-willOpenMenu:withEvent:` on the keyboard web view (the
  working SDK path — no public macOS WK context-menu hook exists); replaced the
  "open … in New Window" items with "open … in New Tab" (parity with
  fix_open_in_new_window_stock_action) and appended Home/Hint-Links/View-Source/
  Add-Bookmark/Copy-URL actions; menu-tree builder lives in Foundation-only
  VimbContextMenu (unit-tested: test_context_menu_build).

### WS-3  Editor async read-back (`editor-command` polish) — `[done]`
- **Goal:** make the external-editor flow work with async editors (the
  `open -t`/TextEdit default) by polling/watching the temp file so edits come
  back; keep blocking editors (vim/\$EDITOR) working. Add a bounded wait so it
  degrades gracefully.
  - Note: VimbEditor now runs a two-phase wait — blocking editors read back on
    process exit; async editors are picked up by a bounded main-run-loop poll
    (content-sensitive change detect). Test injects `editorTempPath`,
    `editorPollInterval`, `editorTimeout` to fake the async write via
    dispatch_after. Both `test_editor_round_trip` and
    `test_editor_async_readback` green.
- **Owns:** `macos/VimbEditor.m`, `macos/VimbEditor.h`,
  `frags/ws3-editor.mk`, `macos/tests/test_behavior.m` (your new test
  `test_editor_async_readback`).
- **Reference:** `src/main.c ex_open` + `input.c`.
- **Memory tag:** `editor`.

### WS-4  Bookmarks browser UI (`bookmark.c` polish) — `[done]`
- **Goal:** add a keyboard-reachable bookmark browser (list + filter + open +
  delete) beyond the existing `:bma`/`:bmr` commands, mirroring the gB-style
  flow used in upstream Linux vimb.
  - Note: VimbBookmarkStore (Foundation CRUD, tested) + VimbBookmarkBrowser
    (AppKit panel) added; reachable via `:bookmarks`, File▸Bookmarks (⌘B).
- **Owns:** `macos/VimbBookmarkStore.m/h`, `macos/VimbBookmarkBrowser.m/h`,
  `frags/ws4-bookmark.mk`, `macos/tests/test_behavior.m` (your new test
  `test_bookmark_store`), `macos/VimbConfig.m` (bookmark-store wiring ONLY if
  the store needs config defaults — prefer self-contained file).
- **Reference:** `src/bookmark.c`, `src/scripts/dom_operations.js`.
- **Memory tag:** `bookmarks`.

### WS-5  Notification permission — `[n/a]`
- **Blocked / not portable:** WKWebView has no per-frame notification-permission
  delegate callback on macOS; desktop notifications route through the app's
  Notification-Center entitlement automatically. Nothing to port. Do not claim.

### WS-6  Non-public settings application — `[n/a]`
- **Blocked / not portable:** `images`, `media-*`, `webaudio`, `webgl`, font
  families, `caret`, etc. have no public WK API, or using them re-triggers the
  KVC-on-`WKPreferences` init hang. Do not claim. Documented in
  `macos/settings-application.md` (memory tag `settings`).

---

## Workbook / claim sheet

Update this table honestly. Claim a row by setting it `[claimed] by <model>`.
Only unclaimed (`[open]`) rows may be claimed. The sequencer (lead) assigns
commit order and does the serial Makefile-fragment includes.

| ID | Stream             | Files owned                      | Status        |
|----|--------------------|----------------------------------|---------------|
| 1  | Completion dropdown| CompletionDropdown.*, frag ws1   | `[done]`       |
| 2  | Context menu       | VimbContextMenu.*, frag ws2      | `[done]`       |
| 3  | Editor read-back   | VimbEditor.*, frag ws3           | `[done]`       |
| 4  | Bookmarks UI       | VimbBookmark*.*, frag ws4        | `[done]`       |
| 5  | Notification perm  | — (not portable)                 | `[n/a]`       |
| 6  | Non-public settings| — (not portable)                 | `[n/a]`       |

---

## Sequencing note (for the lead)

Because `Makefile` and `tests/test_behavior.m` are shared, the **lead** should
execute these serially (not in parallel) while workers develop independently:
1. Add the `frags/` include block and one `frags/<stream>.mk` per claimed stream.
2. Either coordinate the single test-function append points in `test_behavior.m`
   (each stream appends its one function at a distinct, pre-allocated marker)
   or accept that test-file merges are done by the lead.
3. Verify `make -C macos test` and `make -C macos`, then `git push`.

# Settings application on macOS (WKWebView ceiling)

Status reference for which `:set` settings are actually applied to WKWebView
versus registered as accepted-but-inert. Companion to `PARALLEL-SUBAGENTS.md`
WS-6/WS-8 and to the registration table in `VimbConfig.m` (which mirrors
`src/setting.c`'s `setting_add` calls).

Why some settings are inert: GTK vimb writes directly into WebKitGTK's
`WebKitSettings` object property bag. WKWebView exposes only a small, fixed
set of preferences, and touching unknown KVC keys on `WKPreferences` at init
time re-triggers a known WebKit hang. So the port registers every GTK setting
name (config files stay portable) and applies only what has a public API.

## Applied at config time (before the web view exists)

Applied in `KeyboardWebView -initWithFrame:` on the `WKWebViewConfiguration`
/ `WKPreferences`. These cannot change after creation:

| Setting | WK API |
|---|---|
| `print-backgrounds` | `prefs.shouldPrintBackgrounds` (macOS 13.3+) |
| `media-playback-requires-user-gesture` | `mediaTypesRequiringUserActionForPlayback` |
| `cookie-accept` | `httpCookieStore` cookie policy (macOS 14+; "origin" has no desktop equivalent, best-effort Allow) |

## Applied live (runtime changes take effect)

Handled through `VimbConfig -applySetting:value:` and the BrowserWindowController
`:set` dispatch: anything with a native AppKit/WK surface, e.g. `dark-mode`,
`gui-*` styling, `completion-css` / `completion-selected-css`, `statusbar-*`,
fonts and colors.

`completion-hover-css` is an exception: the dropdown is a custom row view with
no hover state, so the value is parsed and stored but never rendered (selected
row styling covers the keyboard/mouse selection path).

## Registered but inert (accepted for config compatibility, no WK effect)

| Setting | GTK backend (`src/setting.c`) | Why inert on macOS |
|---|---|---|
| `caret` | `enable-caret-browsing` (setting.c:97) | No public WK caret-browsing API. Stored, never applied. |
| `cursiv-font` | `cursive-font-family` (setting.c:98) | The GTK key name itself is vimb's historical misspelling of "cursive"; kept verbatim for config parity. No public WK font-family override. |
| `spell-checking` | `webkit_web_context_set_spell_checking_enabled` (setting.c:899) | WKWebView spell checking follows the system Text Replacement / autocorrect settings; no per-view public toggle. |
| `spell-checking-languages` | (setting.c:910) | Same ceiling as above. |
| `images`, `media-*`, `webaudio`, `webgl` | various `WebKitSettings` props | No public WK API without private headers. |

`spell-checking` and `spell-checking-languages` are inert everywhere on the
port: web content follows the system spelling configuration, and the native
input fields (command line, editor) do not consult these settings either.

## Rules for extending

- Register every GTK setting name in `VimbConfig.m` even if inert, so config
  files written for GTK vimb load without errors.
- When a new public WK API appears, move the setting from the inert table to
  the applied tables above and note the minimum macOS version.
- Never KVC arbitrary keys onto `WKPreferences`; that path hangs at init.

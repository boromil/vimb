#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shared /bin/sh runner for all external-command spawning (parity with the
// GTK original's g_spawn_* usage: src/main.c spawn_download_command,
// src/ex.c ex_shellcmd/ex_shellex, src/handler.c handler_handle_uri).
//
// Why this exists (architecture fix):
// 1. Every call site used to build its own NSTask with the URL or file path
//    string-interpolated into a /bin/sh -c argument. A URL containing shell
//    metacharacters ("; rm -rf ~", backticks, "$(...)") would execute — an
//    injection surface driven by remote web content. GTK avoided this by
//    g_shell_parse_argv + argv spawn; here we shell-quote the substituted
//    value instead (single quotes + '\'' escaping, the POSIX-safe encoding).
// 2. The old :shellex read child output with readDataToEndOfFile inside the
//    termination handler. If the child writes more than the pipe buffer
//    (~64KB) it blocks forever, never exits, and the handler never runs:
//    the classic NSTask pipe deadlock. Here output is drained
//    asynchronously (readabilityHandler) *before* we wait for exit.
//
// This class is Foundation-only and unit tested (frags: it is in TEST_SRCS).
@interface VimbTaskRunner : NSObject

// Expands a command template by substituting `value` for the first "%s"
// (shell-quoted), or appending it (also shell-quoted) when the template has
// no "%s". Mirrors g_strdup_printf(cmd, uri) + the appends in the mac port,
// but the substituted value can never break out of its quoting.
+ (NSString *)expandTemplate:(NSString *)template_ value:(NSString *)value;

// POSIX single-quote shell quoting: wraps in '…' and encodes embedded
// single quotes as '\''. Newlines are preserved (quoted). Returns @"''"
// for empty input so callers can rely on a non-empty argument.
+ (NSString *)shellQuote:(NSString *)s;

// Runs `commandLine` through /bin/sh -c, captures stdout+stderr, reports
// exit status. Output is drained asynchronously — safe for any size.
// `completion` is invoked exactly once, on the main queue. Returns NO when
// the process could not be launched (with `error` set).
+ (BOOL)run:(NSString *)commandLine
 environment:(nullable NSDictionary<NSString *, NSString *> *)env
 completion:(void (^ _Nullable)(NSString * _Nullable stdout,
                                NSString * _Nullable stderr,
                                int exitStatus))completion;

// Fire-and-forget spawn (parity with g_spawn_command_line_async). Runs the
// command through /bin/sh -c with a drained-but-discarded output pipe so a
// chatty child can never deadlock on a full pipe. Returns NO on launch
// failure (with `error` set).
+ (BOOL)runAsync:(NSString *)commandLine
  environment:(nullable NSDictionary<NSString *, NSString *> *)env
        error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

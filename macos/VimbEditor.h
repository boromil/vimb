#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// External-editor invoker, ported from command.c command_spawn_editor +
// input_editor_formfiller. Writes `text` to a temp file, runs editor-command
// (%s -> temp path), and after the edit completes returns the edited content.
// Reliable for blocking editors (vim/nano/$EDITOR that write-and-exit) and
// best-effort for async editors (open -t / TextEdit) via a bounded poll/watch
// loop that waits for the temp file to actually change.
@interface VimbEditor : NSObject

// How often the async-editor watch loop re-checks the temp file (seconds).
// Test-only knob; callers use the default. Default 0.25.
@property (nonatomic, assign) NSTimeInterval editorPollInterval;

// Upper bound on how long to wait for an async editor to write back (seconds),
// before giving up and returning the file as-is. Applies only AFTER the spawned
// process exits; a blocking editor that is still running is never cut off.
// Default 30.0.
@property (nonatomic, assign) NSTimeInterval editorTimeout;

// Optional fixed temp-file path. When unset a unique path under the system temp
// dir is auto-generated. Injectable so tests can fake the async write without
// guessing the internal path.
@property (nonatomic, copy, nullable) NSString *editorTempPath;

// Create a temp file with `text`, run `editorCommand` (substituting %s or
// appending the path). completion gets the edited file content + path, or
// nil if the editor failed to launch. Returns NO if spawn failed.
- (BOOL)editText:(NSString *)text
           editorCommand:(NSString *)editorCommand
              completion:(void (^)(NSString * _Nullable edited, NSString * _Nullable path))completion;
@end

NS_ASSUME_NONNULL_END

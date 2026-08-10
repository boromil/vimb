#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// External-editor invoker, ported from command.c command_spawn_editor +
// input_editor_formfiller. Writes `text` to a temp file, runs editor-command
// (%s -> temp path), and on the editor's exit returns the edited content.
// Best-effort for async editors (open -t / TextEdit); reliable for blocking
// ones (vim, nano, $EDITOR).
@interface VimbEditor : NSObject
// Create a temp file with `text`, run `editorCommand` (substituting %s or
// appending the path). completion gets the edited file content + path, or
// nil if the editor failed to launch. Returns NO if spawn failed.
- (BOOL)editText:(NSString *)text
           editorCommand:(NSString *)editorCommand
              completion:(void (^)(NSString * _Nullable edited, NSString * _Nullable path))completion;
@end

NS_ASSUME_NONNULL_END

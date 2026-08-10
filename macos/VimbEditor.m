#import "VimbEditor.h"

@implementation VimbEditor

- (BOOL)editText:(NSString *)text
           editorCommand:(NSString *)editorCommand
              completion:(void (^)(NSString * _Nullable, NSString * _Nullable))completion {
    if (editorCommand.length == 0) { return NO; }
    // Temp file in the system temp dir.
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"vimb-editor-%@.txt", [NSUUID UUID].UUIDString]];
    NSError *werr = nil;
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&werr]) {
        return NO;
    }

    // Substitute %s (or append the path).
    NSString *expanded = editorCommand;
    if ([editorCommand containsString:@"%s"]) {
        expanded = [editorCommand stringByReplacingOccurrencesOfString:@"%s"
                                                            withString:path
                                                               options:0
                                                                 range:[editorCommand rangeOfString:@"%s"]];
    } else {
        expanded = [NSString stringWithFormat:@"%@ '%@'", editorCommand, path];
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sh";
    task.arguments = @[@"-c", expanded];
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = out;
    task.terminationHandler = ^(NSTask *t) {
        (void)t;
        // Read the (possibly edited) file back after the editor exits.
        NSString *edited = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) { completion(edited, path); }
        });
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    };
    @try {
        [task launch];
    } @catch (NSException *e) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return NO;
    }
    return YES;
}

@end

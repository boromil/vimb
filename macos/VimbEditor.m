#import "VimbEditor.h"

@implementation VimbEditor

- (instancetype)init {
    self = [super init];
    if (self) {
        _editorPollInterval = 0.25;
        _editorTimeout = 30.0;
    }
    return self;
}

- (BOOL)editText:(NSString *)text
           editorCommand:(NSString *)editorCommand
              completion:(void (^)(NSString * _Nullable, NSString * _Nullable))completion {
    if (editorCommand.length == 0) { return NO; }

    // Temp file. Tests can inject a fixed path; otherwise auto-generate one in
    // the system temp dir.
    NSString *path = self.editorTempPath;
    if (path.length == 0) {
        path = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"vimb-editor-%@.txt", [NSUUID UUID].UUIDString]];
    }
    NSError *werr = nil;
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&werr]) {
        return NO;
    }

    // Baseline snapshot of the freshly-written file, so we can tell when an
    // editor has actually written something back (content-sensitive, so it works
    // even when the filesystem truncates mtime to whole seconds).
    NSData *originalData = [[NSData alloc] initWithContentsOfFile:path];

    // Capture the injection knobs once for use in the async callbacks.
    NSTimeInterval pollInterval = self.editorPollInterval;
    NSTimeInterval timeout = self.editorTimeout;
    NSDate *spawnDate = [NSDate date];

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

    __block BOOL done = NO;      // guard against double completion
    __block NSTimer *pollTimer = nil;

    void (^finish)(NSString *_Nullable) = ^(NSString *result) {
        if (done) { return; }
        done = YES;
        [pollTimer invalidate];
        pollTimer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) { completion(result, path); }
        });
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    };
    void (^finishIfEdited)(void) = ^(void) {
        NSData *current = [[NSData alloc] initWithContentsOfFile:path];
        if (current != nil && ![current isEqualToData:originalData]) {
            NSString *edited = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            finish(edited);
        }
    };

    task.terminationHandler = ^(NSTask *t) {
        (void)t;
        // Blocking editor (vim/nano/$EDITOR): the process wrote the file and
        // exited. Read the edited content straight back.
        finishIfEdited();

        // Async editor (open -t / TextEdit): the launcher exited without writing
        // anything; the real editor writes the temp file later. Start a bounded
        // watch loop on the main run loop to pick that write up.
        if (!done) {
            NSDate *deadline = [spawnDate dateByAddingTimeInterval:timeout];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done || pollTimer != nil) { return; }
                NSTimer *timer = [NSTimer timerWithTimeInterval:pollInterval
                                                        repeats:YES
                                                          block:^(NSTimer *tm) {
                    (void)tm;
                    finishIfEdited();
                    if (!done && [deadline timeIntervalSinceNow] <= 0) {
                        // Bounded wait: give up and return whatever is there.
                        NSString *edited = [NSString stringWithContentsOfFile:path
                                                                     encoding:NSUTF8StringEncoding
                                                                        error:nil];
                        finish(edited);
                    }
                }];
                [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
                pollTimer = timer;
            });
        }
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

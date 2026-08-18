#import "VimbTaskRunner.h"

@implementation VimbTaskRunner

+ (NSString *)shellQuote:(NSString *)s {
    if (s.length == 0) { return @"''"; }
    // Encode as a single-quoted string; the only character that can't appear
    // inside single quotes is the single quote itself, encoded as: '\''
    // (close quote, escaped quote, reopen quote).
    NSString *inner = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", inner];
}

+ (NSString *)expandTemplate:(NSString *)template_ value:(NSString *)value {
    NSString *quoted = [self shellQuote:value];
    NSRange first = [template_ rangeOfString:@"%s"];
    if (first.location != NSNotFound) {
        return [template_ stringByReplacingOccurrencesOfString:@"%s"
                                                     withString:quoted
                                                        options:0
                                                          range:first];
    }
    return [NSString stringWithFormat:@"%@ %@", template_, quoted];
}

// Drains a pipe asynchronously into a mutable data buffer. The handler is
// called with nil data at EOF and clears itself; the caller combines the
// per-pipe completion blocks to know when both streams are done.
static void drainPipe(NSPipe *pipe, NSMutableData *sink, void (^onEOF)(void)) {
    __block BOOL done = NO;
    [pipe.fileHandleForReading setReadabilityHandler:^(NSFileHandle *h) {
        if (done) { return; }
        @try {
            NSData *chunk = [h availableData];
            if (chunk.length == 0) {
                // EOF
                done = YES;
                h.readabilityHandler = nil;
                onEOF();
            } else {
                [sink appendData:chunk];
            }
        } @catch (NSException *e) {
            done = YES;
            h.readabilityHandler = nil;
            onEOF();
        }
    }];
}

+ (BOOL)run:(NSString *)commandLine
 environment:(nullable NSDictionary<NSString *, NSString *> *)env
 completion:(void (^ _Nullable)(NSString * _Nullable, NSString * _Nullable, int))completion {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[ @"-c", commandLine ];
    if (env) { task.environment = env; }

    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;

    NSMutableData *outData = [NSMutableData data];
    NSMutableData *errData = [NSMutableData data];

    __block NSInteger streamsOpen = 2;
    void (^oneStreamDone)(void) = ^{
        if (--streamsOpen == 0 && completion) {
            NSString *out = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
            NSString *err = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(out, err, (int)task.terminationStatus);
            });
            // Break the retain cycle the readability handlers held.
                outPipe.fileHandleForReading.readabilityHandler = nil;
                errPipe.fileHandleForReading.readabilityHandler = nil;
            }
    };

    drainPipe(outPipe, outData, oneStreamDone);
    drainPipe(errPipe, errData, oneStreamDone);

    NSError *launchErr = nil;
    if (![task launchAndReturnError:&launchErr]) {
        // Clean up the drains we just installed.
        outPipe.fileHandleForReading.readabilityHandler = nil;
        errPipe.fileHandleForReading.readabilityHandler = nil;
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil, -1);
            });
        }
        return NO;
    }
    return YES;
}

+ (BOOL)runAsync:(NSString *)commandLine
  environment:(nullable NSDictionary<NSString *, NSString *> *)env
        error:(NSError * _Nullable * _Nullable)error {
    // Fire-and-forget, but with a drained (discarded) output pipe: without a
    // reader, a child that writes > pipe-buffer bytes blocks forever on
    // write() and appears to hang.
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[ @"-c", commandLine ];
    if (env) { task.environment = env; }
    NSPipe *outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = outPipe;
    drainPipe(outPipe, [NSMutableData data], ^{});
    NSError *launchErr = nil;
    if (![task launchAndReturnError:&launchErr]) {
        if (error) { *error = launchErr; }
        return NO;
    }
    return YES;
}

@end

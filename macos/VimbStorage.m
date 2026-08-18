#import "VimbStorage.h"

// Default debounce interval for disk writes.
static const NSTimeInterval kVimbStorageDefaultFlushDelay = 0.5;

// Per-path write serialization: atomic writes are per-file safe, but two
// stores pointing at the SAME path (or a flush racing a flush) must not
// interleave. Writes hop to a private serial queue; ordering per path is
// preserved because the payload is captured by value at schedule time.
static NSString *storageWriteQueueLabel = @"org.vimb.storage.write";
static dispatch_queue_t storageWriteQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create([storageWriteQueueLabel UTF8String], DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Tracks live store instances for +flushAll (weak, so stores are not kept
// alive by the registry; main-thread only, same as the rest of the API).
static NSHashTable< VimbStorage * > *liveStores(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

static NSTimeInterval _flushDelay = kVimbStorageDefaultFlushDelay;

@implementation VimbStorage {
    NSMutableArray<NSString *> *_cache;   // lazy: nil until first read
    BOOL _dirty;                          // cache has changes not on disk
    dispatch_source_t _debounce;          // coalesces rapid mutations
}

// Class-property accessors (class properties are not auto-synthesized).
+ (NSTimeInterval)flushDelay { return _flushDelay; }
+ (void)setFlushDelay:(NSTimeInterval)d { _flushDelay = d; }

+ (NSString *)appSupportDir {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSHomeDirectory();
    NSString *dir = [[base stringByAppendingPathComponent:@"vimb"] stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSString *)cacheDir {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSHomeDirectory();
    NSString *dir = [[base stringByAppendingPathComponent:@"vimb"] stringByStandardizingPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (instancetype)initWithName:(NSString *)name {
    return [self initWithName:name directory:[VimbStorage appSupportDir]];
}

- (instancetype)initWithName:(NSString *)name directory:(NSString *)baseDir {
    self = [super init];
    if (self) {
        NSString *dir = [baseDir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        _dir = dir;
        @synchronized(liveStores()) {
            [liveStores() addObject:self];
        }
    }
    return self;
}

+ (VimbStorage *)storageInTempDirectoryWithName:(NSString *)name {
    NSString *base = NSTemporaryDirectory();
    NSString *baseDir = [[base stringByAppendingPathComponent:@"vimb-tests"]
                         stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:baseDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [[VimbStorage alloc] initWithName:name directory:baseDir];
}

#pragma mark - Cache

// All access is main-thread (every caller lives on the main thread; tests
// are single-threaded). The assert documents that contract cheaply.
- (NSMutableArray<NSString *> *)cachedLines {
    NSAssert([NSThread isMainThread], @"VimbStorage is main-thread only");
    if (!_cache) {
        NSString *content = [NSString stringWithContentsOfFile:self.dir encoding:NSUTF8StringEncoding error:nil];
        NSMutableArray *r = [NSMutableArray array];
        if (content) {
            for (NSString *l in [content componentsSeparatedByString:@"\n"]) {
                if (l.length) { [r addObject:l]; }
            }
        }
        _cache = r;
    }
    return _cache;
}

- (NSArray<NSString *> *)lines {
    return [self cachedLines];
}

- (void)markDirty {
    _dirty = YES;
    if (self.class.flushDelay <= 0) {
        // Tests / immediate mode: no timer, write synchronously.
        [self flush:nil];
        return;
    }
    // Recreate the debounce timer for each burst (resuming an already-active
    // dispatch source would over-resume and trap in libdispatch).
    if (_debounce) {
        dispatch_source_cancel(_debounce);
        _debounce = nil;
    }
    _debounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                       dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_debounce, ^{
        [weakSelf flush:nil];
    });
    dispatch_source_set_timer(_debounce,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.class.flushDelay * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(_debounce);
}

- (BOOL)flush:(NSError * _Nullable * _Nullable)error {
    NSAssert([NSThread isMainThread], @"VimbStorage is main-thread only");
    if (_debounce) {
        dispatch_source_cancel(_debounce);
        _debounce = nil;
    }
    if (!_dirty) { return YES; }
    NSArray<NSString *> *snapshot = [_cache copy];
    _dirty = NO;
    __block BOOL ok = YES;
    __block NSError *writeErr = nil;
    dispatch_sync(storageWriteQueue(), ^{
        NSString *joined = [snapshot componentsJoinedByString:@"\n"];
        if (joined.length) { joined = [joined stringByAppendingString:@"\n"]; }
        ok = [joined writeToFile:self.dir atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
    });
    if (!ok && error) { *error = writeErr; }
    return ok;
}

+ (void)flushAll {
    NSArray<VimbStorage *> *stores;
    @synchronized(liveStores()) {
        stores = [liveStores() allObjects];
    }
    for (VimbStorage *s in stores) {
        [s flush:nil];
    }
}

#pragma mark - Mutations (cache-first, debounced persist)

- (void)writeAll:(NSArray<NSString *> *)lines {
    NSMutableArray *copy = [lines mutableCopy];
    _cache = copy;
    [self markDirty];
}

- (void)prepend:(NSString *)line max:(NSUInteger)max {
    NSMutableArray *ls = [self cachedLines];
    [ls removeObject:line];
    [ls insertObject:line atIndex:0];
    if (max > 0 && ls.count > max) { [ls removeObjectsInRange:NSMakeRange(max, ls.count - max)]; }
    [self markDirty];
}

- (void)append:(NSString *)line {
    [[self cachedLines] addObject:line];
    [self markDirty];
}

- (void)push:(NSString *)line max:(NSUInteger)max {
    [self prepend:line max:max];
}

- (nullable NSString *)top {
    return [self cachedLines].firstObject;
}

- (void)removeLine:(NSString *)line {
    [[self cachedLines] removeObject:line];
    [self markDirty];
}

- (nullable NSString *)popLast {
    NSMutableArray *ls = [self cachedLines];
    if (ls.count == 0) { return nil; }
    NSString *last = ls[0];
    [ls removeObjectAtIndex:0];
    [self markDirty];
    return last;
}

- (void)clear {
    _cache = [NSMutableArray array];
    if (_debounce) {
        dispatch_source_cancel(_debounce);
        _debounce = nil;
    }
    // Remove the file for real (a debounced empty write would also work, but
    // clearing is expected to free the file immediately, e.g. :cleardata).
    dispatch_sync(storageWriteQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:self.dir error:nil];
    });
    _dirty = NO;
}

@end

#import "VimbEngine.h"

@implementation VSetting
- (instancetype)initWithName:(NSString *)name type:(VSettingType)type value:(id)value apply:(void (^_Nullable)(NSString *, id))apply {
    self = [super init];
    if (self) {
        _name = [name copy];
        _type = type;
        _value = value;
        _apply = [apply copy];
    }
    return self;
}
@end

@implementation VimbRegisters {
    NSMutableDictionary<NSString *, NSString *> *_regs;
}
- (instancetype)init { self = [super init]; if (self) { _regs = [NSMutableDictionary dictionary]; } return self; }
- (void)set:(NSString *)text forKey:(unichar)key {
    _regs[[NSString stringWithCharacters:&key length:1]] = text;
}
- (NSString *)get:(unichar)key {
    return _regs[[NSString stringWithCharacters:&key length:1]];
}
@end

@implementation VimbMarks {
    NSMutableDictionary<NSString *, NSNumber *> *_local;
    NSMutableDictionary<NSString *, NSString *> *_global;
    NSMutableArray<NSString *> *_globalOrder; // most-recent '0 first
}
- (instancetype)init {
    self = [super init];
    if (self) { _local = [NSMutableDictionary dictionary]; _global = [NSMutableDictionary dictionary]; _globalOrder = [NSMutableArray array]; }
    return self;
}
- (void)setLocal:(unichar)c top:(double)top {
    _local[[NSString stringWithCharacters:&c length:1]] = @(top);
}
- (double)getLocal:(unichar)c {
    return [_local[[NSString stringWithCharacters:&c length:1]] doubleValue];
}
- (void)setGlobal:(unichar)c uri:(NSString *)uri {
    NSString *k = [NSString stringWithCharacters:&c length:1];
    if (uri) {
        _global[k] = uri;
        [_globalOrder removeObject:k];
        [_globalOrder insertObject:k atIndex:0];
        if (_globalOrder.count > 10) {
            NSString *old = _globalOrder.lastObject;
            [_globalOrder removeLastObject];
            [_global removeObjectForKey:old];
        }
    }
}
- (NSString *)getGlobal:(unichar)c {
    return _global[[NSString stringWithCharacters:&c length:1]];
}
@end

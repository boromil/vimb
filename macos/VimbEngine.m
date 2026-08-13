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
    // Uppercase register ('"Ay) appends to the lowercase register with a \n
    // separator (vb_register_add, src/main.c:621-640).
    if (key >= 'A' && key <= 'Z') {
        NSString *lower = [NSString stringWithCharacters:(unichar[]){key + 32} length:1];
        NSString *existing = _regs[lower];
        if (existing.length) {
            _regs[lower] = [NSString stringWithFormat:@"%@\n%@", existing, text ?: @""];
            return;
        }
        _regs[lower] = text ?: @"";
        return;
    }
    _regs[[NSString stringWithCharacters:&key length:1]] = text;
}
- (NSString *)get:(unichar)key {
    return _regs[[NSString stringWithCharacters:&key length:1]];
}
@end

@implementation VimbMarks {
    NSMutableDictionary<NSString *, NSNumber *> *_local;
    NSMutableDictionary<NSString *, NSString *> *_global;
}
- (instancetype)init {
    self = [super init];
    if (self) { _local = [NSMutableDictionary dictionary]; _global = [NSMutableDictionary dictionary]; }
    return self;
}
- (void)setLocal:(unichar)c top:(double)top {
    _local[[NSString stringWithCharacters:&c length:1]] = @(top);
}
- (double)getLocal:(unichar)c {
    return [_local[[NSString stringWithCharacters:&c length:1]] doubleValue];
}
// Global marks are uppercase letters 'A'..'Z (GLOBAL_MARK_CHARS, src/main.h:66)
// with no cap: setting a letter overwrites/replaces it exactly as GTK's
// global_marks[] does.
- (void)setGlobal:(unichar)c uri:(NSString *)uri {
    if (uri) {
        _global[[NSString stringWithCharacters:&c length:1]] = uri;
    }
}
- (NSString *)getGlobal:(unichar)c {
    return _global[[NSString stringWithCharacters:&c length:1]];
}
@end

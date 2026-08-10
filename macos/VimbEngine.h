#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VSettingType) { VSettingBool, VSettingInt, VSettingChar, VSettingList };

// A single vimb setting, mirroring setting.c's Setting + setter concept.
@interface VSetting : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) VSettingType type;
@property(nonatomic, strong) id value;              // NSNumber/NSString/NSArray
@property(nonatomic, copy, nullable) void (^apply)(NSString *name, id value);
- (instancetype)initWithName:(NSString *)name type:(VSettingType)type value:(id)value apply:(void (^ _Nullable)(NSString *, id))apply;
@end

// Registers (yank/paste) and marks, ported from State.reg / marks handling.
@interface VimbRegisters : NSObject
- (void)set:(NSString *_Nullable)text forKey:(unichar)key;
- (nullable NSString *)get:(unichar)key;
@end

@interface VimbMarks : NSObject
// local marks: 'a..'z mapped to scroll-top in doc (pixel)
- (void)setLocal:(unichar)c top:(double)top;
- (double)getLocal:(unichar)c;
// global marks: '0..'9 mapped to URI
- (void)setGlobal:(unichar)c uri:(NSString *_Nullable)uri;
- (nullable NSString *)getGlobal:(unichar)c;
@end

NS_ASSUME_NONNULL_END

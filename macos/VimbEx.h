#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Executes vimb ex commands (":"-prefixed command lines). Faithful port of
// ex.c's command table + dispatch. Returns a *success* flag that the caller
// uses to decide whether to keep the command-line input (CMD_KEEPINPUT).
@protocol VimbExActor <NSObject>
- (void)exOpen:(NSString *)arg newTab:(BOOL)newTab;
- (void)exSet:(NSString *)fullArg;
- (void)exCloseActiveTab;
- (void)exNextTab;
- (void)exPrevTab;
- (void)exFirstTab;
- (void)exLastTab;
- (void)exReload;
- (void)exStop;
- (void)exHome;
- (void)exQuit;
- (void)exQuitAll;
- (void)exEval:(NSString *)js;
- (void)exShell:(NSString *)arg;
- (void)exMessage:(NSString *)msg error:(BOOL)error;
- (void)exSavePage:(nullable NSString *)path;
- (void)exRegisterList;
- (void)exSource:(nullable NSString *)path;
- (void)exQueue:(NSString *)cmd arg:(nullable NSString *)arg;
- (void)exShowMessages;
- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title;
- (void)exBookmarkRemove:(NSString *)match;
@end

@interface VimbEx : NSObject
@property(nonatomic, weak, nullable) id<VimbExActor> actor;
// Returns YES if user input should be retained (i.e. CMD_KEEPINPUT).
- (BOOL)runCommand:(NSString *)command;
- (NSString *)expandToken:(NSString *)token;    // % / # expansion
- (NSArray<NSString *> *)commandNames;
// Resolve a possibly-abbreviated command name (parse_command_name semantics).
- (nullable NSString *)matchCommand:(NSString *)name;
@end

NS_ASSUME_NONNULL_END

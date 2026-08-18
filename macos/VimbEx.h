#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class VimbConfig;

// Result/lifecycle bitmask returned by VimbEx.runCommand: and reported through
// the optional actor result channel. Mirrors src/main.h's VbCmdResult:
// CMD_ERROR=0, CMD_SUCCESS=0x01, CMD_KEEPINPUT=0x02 ("don't clear the inputbox").
typedef NS_OPTIONS(NSUInteger, VimbExCmdResult) {
    VimbExCmdResultError     = 0,
    VimbExCmdResultSuccess   = 1 << 0, // command executed successfully
    VimbExCmdResultKeepInput = 1 << 1, // don't clear the command input box
};

// Executes vimb ex commands (":"-prefixed command lines). Faithful port of
// ex.c's command table + dispatch. Returns the command result bitmask
// (CMD_SUCCESS | CMD_KEEPINPUT), which the caller uses to decide whether to
// keep the input box text.
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
- (void)exQuit:(BOOL)bang;
- (void)exQuitAll:(BOOL)bang;
- (void)exEval:(NSString *)js suppressOutput:(BOOL)suppress;
- (void)exShell:(NSString *)arg async:(BOOL)async;
- (void)exNormal:(NSString *)keys applyMapping:(BOOL)applyMapping;
- (void)exClearData:(nonnull NSString *)types;
- (void)exPrint;
- (void)exHandlerAdd:(NSString *)scheme command:(NSString *)command success:(nullable void (^)(BOOL))callback;
- (void)exHandlerRemove:(NSString *)scheme success:(nullable void (^)(BOOL))callback;
- (void)exMessage:(NSString *)msg error:(BOOL)error;
- (void)exSavePage:(nullable NSString *)path;
- (void)exRegisterList;
- (void)exSource:(nullable NSString *)path;
- (void)exQueue:(NSString *)cmd arg:(nullable NSString *)arg;
- (void)exShowMessages;
- (void)exBookmarkAdd:(NSString *)url title:(NSString *)title;
- (void)exBookmarkCurrent:(nullable NSString *)tags;
- (void)exUnbookmark:(nullable NSString *)match;
// Optional: open the bookmark browser panel. Implemented by the window
// controller; treated as a no-op by actors that don't support it.
@optional
- (void)exShowBookmarks;
// Uniform async result/lifecycle channel. Commands whose success/failure is
// only known after an async operation (e.g. eval, handler add/remove) report
// through this instead of ad-hoc exMessage:/completion blocks. Optional so
// existing actor implementations are unaffected.
- (void)exReportResult:(VimbExCmdResult)result message:(nullable NSString *)message;
@end

@interface VimbEx : NSObject
@property(nonatomic, weak, nullable) id<VimbExActor> actor;
// Config the engine mutates for :map/:unmap/:shortcut-*. App code uses the
// shared config; tests inject an isolated instance. Nil falls back to
// [VimbConfig shared] so bare [[VimbEx alloc] init] keeps working.
@property(nonatomic, strong, nullable) VimbConfig *config;
// Executes a command line; returns the result bitmask (VimbExCmdResult).
- (VimbExCmdResult)runCommand:(NSString *)command;
- (NSString *)expandToken:(NSString *)token;    // % / # expansion
- (NSArray<NSString *> *)commandNames;
// Resolve a possibly-abbreviated command name (parse_command_name semantics).
- (nullable NSString *)matchCommand:(NSString *)name;
@end

NS_ASSUME_NONNULL_END

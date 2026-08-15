#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The parsed result of an ex command line, mirroring ex.c's ExArg struct.
// Fields that a command did not populate (per its flags) are nil/empty.
@interface VimbExArg : NSObject
@property(nonatomic, readonly) NSString *command;   // full (unabbreviated) command name, or nil
@property(nonatomic, readonly) NSInteger count;     // leading numeric count (:Ncmd), 0 when absent
@property(nonatomic, readonly) BOOL bang;           // post-command '!' (:quit!, :normal!)
@property(nonatomic, readonly, nullable) NSString *lhs;  // left-hand side arg (EX_FLAG_LHS)
@property(nonatomic, readonly, nullable) NSString *rhs;  // right-hand side arg (EX_FLAG_RHS/CMD)
// The raw remainder of the line after the command name (and bang), trimmed of
// leading whitespace but otherwise unmodified. Kept so the macos side can pass
// an unchanged combined arg string to dispatch branches written against GTK's
// "everything after the name" convention before lhs/rhs split.
@property(nonatomic, readonly, nullable) NSString *rest;
// True when the command-name parse found no matching table command.
@property(nonatomic, readonly) BOOL unknownCommand;
// When the parsed command's rhs terminated at an unescaped '|' (a non-command-
// list command), the remaining text after that '|' (leading whitespace
// trimmed). Nil otherwise. Lets the caller chain commands like GTK's
// ex_run_string loop (:set a=1 | set b=2). Command-list (EX_FLAG_CMD) commands
// treat '|' as literal rhs content and never set this.
@property(nonatomic, readonly, nullable) NSString *nextCommand;
@end

// Pure ex-command-line parser ported from src/ex.c (parse_command_name,
// parse_bang, parse_count, parse_lhs, parse_rhs over the commands[] table).
// Foundation-only so it is unit-testable in the harness.
@interface VimbExParser : NSObject

// Parses a raw command line (with or without a leading ':'). If the command
// name does not abbreviate to any table entry, `unknownCommand` is set and
// `command` is nil (the caller decides whether to treat the line as a URL).
+ (VimbExArg *)parseLine:(NSString *)line;

// Resolve a possibly-abbreviated name to the full table command name using
// ex.c's first-prefix-wins rule (an exact-length match wins over a longer
// prefix). Returns nil when nothing matches.
+ (nullable NSString *)matchCommandForName:(NSString *)name;

// All command names in table order (for completion / listing).
+ (NSArray<NSString *> *)commandNames;

// :cleardata data-type names recognized by ex_cleardata (src/ex.c:930-943).
// Shared for the dispatch validation in VimbEx and the WK mapping in the
// window controller; keeps the name set in one place.
+ (NSArray<NSString *> *)cleardataTypeNames;

// Port of src/util.c util_parse_expansion for tilde (~, ~/, ~user) and dollar
// ($VAR, ${VAR}) expansion with backslash escaping. Applied to ex-command rhs
// for commands carrying EX_FLAG_EXP (save, shellcmd, shellex, source).
// Foundation-only and deterministic (no passwd lookup: ~user falls through to
// the literal text, ~ and ~/ resolve via the HOME environment variable).
+ (NSString *)expandPathVariableInString:(NSString *)s;

@end

NS_ASSUME_NONNULL_END

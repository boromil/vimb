#import <Cocoa/Cocoa.h>
#import "BrowserWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface VimbAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSMutableArray<BrowserWindowController *> *controllers;
@end

NS_ASSUME_NONNULL_END

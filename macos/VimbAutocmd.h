#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// vimb autocmd events (mirrors autocmd.h AuEvent).
typedef NS_ENUM(NSInteger, VAuEvent) {
    VAuAll = 0,
    VAuLoadStarting,
    VAuLoadStarted,
    VAuLoadCommitted,
    VAuLoadFinished,
    VAuDownloadStarted,
    VAuDownloadFinished,
    VAuDownloadFailed,
};

@class AuEntry;

// Manages :autocmd/:augroup registrations and fires them on load/download
// events, mirroring autocmd.c.
@interface VimbAutocmd : NSObject
@property(nonatomic, copy, nullable) void (^executor)(NSString *excmd);
@property(nonatomic, copy, nullable) void (^reporter)(NSString *msg, BOOL error);

- (BOOL)parseAutocmdLine:(NSString *)line;
- (BOOL)parseAugroupLine:(NSString *)line;
- (BOOL)hasEvent:(VAuEvent)event;
- (void)fireEvent:(VAuEvent)event uri:(nullable NSString *)uri;
@end

NS_ASSUME_NONNULL_END

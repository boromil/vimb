#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Result of resolving a permission request against a config option.
typedef NS_ENUM(NSInteger, VimbPermissionDecision) {
    VimbPermissionGrant,   // allow immediately
    VimbPermissionDeny,    // reject immediately
    VimbPermissionPrompt,  // ask the user
};

// Which capture device a media permission request concerns. Mirrors the three
// WKMediaCaptureType cases relevant to vimb, kept Foundation-only so the policy
// stays testable without WebKit.
typedef NS_ENUM(NSInteger, VimbCaptureKind) {
    VimbCaptureMicrophone,
    VimbCaptureCamera,
    VimbCaptureCameraAndMicrophone,
};

// Port of the permission-decision half of on_permission_request in src/main.c
// and the geolocation/media-stream option handling in src/setting.c. Pure
// functions: no AppKit/WebKit dependencies.
@interface VimbPermissionPolicy : NSObject

// geolocation option is "ask" (default), "always" or "never".
+ (VimbPermissionDecision)geolocationDecisionForOption:(NSString *)option;

// media-stream setting (default NO). When off, camera/microphone access is
// denied outright (vimb gates the requests via enable-media-stream); when on,
// the user is prompted (no ask/always/never knob exists for media in vimb).
+ (VimbPermissionDecision)mediaCaptureDecisionForEnabled:(BOOL)enabled;

// Human-readable fragment for the prompt, matching vimb's user-media messages.
+ (NSString *)mediaCapturePromptForKind:(VimbCaptureKind)kind;

@end

NS_ASSUME_NONNULL_END

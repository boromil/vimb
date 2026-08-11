#import "VimbPermissionPolicy.h"

@implementation VimbPermissionPolicy

+ (VimbPermissionDecision)geolocationDecisionForOption:(NSString *)option {
    if ([option isEqualToString:@"always"]) {
        return VimbPermissionGrant;
    }
    if ([option isEqualToString:@"never"]) {
        return VimbPermissionDeny;
    }
    // "ask" (default) and any unrecognised value fall through to a prompt.
    return VimbPermissionPrompt;
}

+ (VimbPermissionDecision)mediaCaptureDecisionForEnabled:(BOOL)enabled {
    if (!enabled) {
        return VimbPermissionDeny;
    }
    return VimbPermissionPrompt;
}

+ (NSString *)mediaCapturePromptForKind:(VimbCaptureKind)kind {
    switch (kind) {
        case VimbCaptureMicrophone:
            return @"access the microphone";
        case VimbCaptureCamera:
            return @"access you webcam";  // wording matches vimb
        case VimbCaptureCameraAndMicrophone:
            return @"access the camera and microphone";
    }
    return @"access the camera and microphone";
}

@end

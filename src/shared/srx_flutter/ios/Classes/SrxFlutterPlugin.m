#import "SrxFlutterPlugin.h"
#if __has_include(<srx_flutter/srx_flutter-Swift.h>)
#import <srx_flutter/srx_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "srx_flutter-Swift.h"
#endif

@implementation SrxFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSrxFlutterPlugin registerWithRegistrar:registrar];
}
@end

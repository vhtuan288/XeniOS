/**
 ******************************************************************************
 * Xenia : Xbox 360 Emulator Research Project                                 *
 ******************************************************************************
 * Copyright 2026 Ben Vanik. All rights reserved.                             *
 * Released under the BSD license - see LICENSE in the root for more details. *
 ******************************************************************************
 */

#import "xenia/ui/ios/jit_enabler/xe_builtin_jit_settings.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#include <cstring>

#include "xenia/base/logging.h"
#include "xenia/ui/ios/jit_enabler/StikJITExtensionLauncher.h"
#include "xenia/ui/ios/jit_enabler/pairing_shape.h"

namespace {

void PresentMessage(UIViewController* presenter, NSString* title, NSString* message) {
  if (!presenter) {
    return;
  }
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:title
                                          message:message
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert button: OK")
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [presenter presentViewController:alert animated:YES completion:nil];
}

NSString* StageText(const char* word) {
  if (std::strcmp(word, "connecting") == 0) {
    return NSLocalizedString(@"Connecting to this device…", @"Built-in JIT stage");
  }
  if (std::strcmp(word, "pairing") == 0) {
    return NSLocalizedString(@"Checking the pairing file…", @"Built-in JIT stage");
  }
  if (std::strcmp(word, "downloading") == 0) {
    return NSLocalizedString(@"Downloading the Developer Disk Image…", @"Built-in JIT stage");
  }
  if (std::strcmp(word, "mounting") == 0) {
    return NSLocalizedString(@"Mounting the Developer Disk Image…", @"Built-in JIT stage");
  }
  if (std::strcmp(word, "checking") == 0) {
    return NSLocalizedString(@"Checking the Developer Disk Image…", @"Built-in JIT stage");
  }
  return NSLocalizedString(@"Working…", @"Built-in JIT stage");
}

NSString* DiskImageResultText(int32_t op, const armsx3_jit_enabler_ddi_result& r) {
  auto is = [&r](const char* word) { return std::strcmp(r.result, word) == 0; };
  if (is("ready")) {
    return op == ARMSX3_JIT_DDI_OP_MOUNT
               ? NSLocalizedString(@"The Developer Disk Image is mounted. Restart XeniOS to turn "
                                   @"on JIT.",
                                   @"Built-in JIT result")
               : NSLocalizedString(@"Everything is ready. XeniOS turns on JIT by itself when it "
                                   @"starts.",
                                   @"Built-in JIT result");
  }
  if (is("unreachable")) {
    return NSLocalizedString(@"This device couldn't be reached. Turn on LocalDevVPN and try "
                             @"again.",
                             @"Built-in JIT result");
  }
  if (is("pairing")) {
    if (std::strcmp(r.reason, "pairing-absent") == 0) {
      return NSLocalizedString(@"Import a pairing file first.", @"Built-in JIT result");
    }
    return NSLocalizedString(@"This device rejected the pairing file. Make a new one for this "
                             @"device and import it.",
                             @"Built-in JIT result");
  }
  if (is("unmounted")) {
    return NSLocalizedString(@"The pairing file works, but the Developer Disk Image isn't "
                             @"mounted. Tap Mount Developer Disk Image.",
                             @"Built-in JIT result");
  }
  if (is("download")) {
    return NSLocalizedString(@"The Developer Disk Image couldn't be downloaded. Check the "
                             @"internet connection and try again.",
                             @"Built-in JIT result");
  }
  if (is("mount")) {
    return NSLocalizedString(@"The Developer Disk Image couldn't be mounted.",
                             @"Built-in JIT result");
  }
  if (std::strcmp(r.reason, "start-failed") == 0 && getenv("LC_HOME_PATH") != nullptr) {
    return NSLocalizedString(@"The JIT helper couldn't start. Use LiveContainer 3.8.13 or "
                             @"later, turn on Helper Process Support for XeniOS and open it "
                             @"full screen.",
                             @"Built-in JIT result");
  }
  return [NSString stringWithFormat:NSLocalizedString(@"Failed (%s).", @"Built-in JIT result"),
                                    r.reason];
}

void RunDiskImageOperation(UIViewController* presenter, int32_t op, NSString* title) {
  UIAlertController* progress =
      [UIAlertController alertControllerWithTitle:title
                                          message:StageText("connecting")
                                   preferredStyle:UIAlertControllerStyleAlert];
  [presenter presentViewController:progress animated:YES completion:nil];
  [progress retain];
  [presenter retain];
  NSString* title_copy = [title copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    armsx3_jit_enabler_ddi_result result;
    std::memset(&result, 0, sizeof(result));
    armsx3_jit_enabler_ddi(
        op,
        ^(const char* word) {
          NSString* text = StageText(word);
          dispatch_async(dispatch_get_main_queue(), ^{
            progress.message = text;
          });
        },
        &result);
    XELOGI("iOS: built-in JIT disk image op {}: {} ({})", op, result.result, result.reason);
    NSString* message = DiskImageResultText(op, result);
    [message retain];
    dispatch_async(dispatch_get_main_queue(), ^{
      [progress dismissViewControllerAnimated:YES
                                   completion:^{
                                     PresentMessage(presenter, title_copy, message);
                                     [message release];
                                     [title_copy release];
                                     [presenter release];
                                   }];
      [progress release];
    });
  });
}

}  // namespace

@interface XeBuiltInJITPairingPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, assign) UIViewController* presenter;
@property(nonatomic, copy) void (^done)(void);
@end

@implementation XeBuiltInJITPairingPickerDelegate

- (void)dealloc {
  [_done release];
  [super dealloc];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
  objc_setAssociatedObject(controller, @selector(presenter), nil, OBJC_ASSOCIATION_RETAIN);
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  NSURL* url = urls.firstObject;
  NSData* data = nil;
  if (url) {
    const BOOL scoped = [url startAccessingSecurityScopedResource];
    NSFileHandle* handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    data = [handle readDataUpToLength:ARMSX3_PAIRING_MAX_BYTES + 1 error:nil];
    [handle closeAndReturnError:nil];
    if (scoped) {
      [url stopAccessingSecurityScopedResource];
    }
  }
  XeBuiltInJITImportPairingData(self.presenter, data, "picker", self.done);
  objc_setAssociatedObject(controller, @selector(presenter), nil, OBJC_ASSOCIATION_RETAIN);
}

@end

bool XeBuiltInJITAvailable() { return armsx3_jit_enabler_is_embedded() != 0; }

std::string XeBuiltInJITPairingStatusText() {
  switch (armsx3_jit_enabler_pairing_status()) {
    case ARMSX3_JIT_PAIRING_STATUS_OWN:
      return "Pairing file imported.";
    case ARMSX3_JIT_PAIRING_STATUS_OWN_INVALID:
      return "The imported file isn't a Remote Pairing file. Import another one.";
    case ARMSX3_JIT_PAIRING_STATUS_SIDESTORE:
      return "Using SideStore's pairing file from LiveContainer.";
    default:
      return "No pairing file. Import a Remote Pairing file (pairingFile.plist) made for this "
             "device.";
  }
}

void XeBuiltInJITImportPairingData(UIViewController* presenter, NSData* data, const char* origin,
                                   void (^done)(void)) {
  const int result = data.length > 0
                         ? armsx3_jit_enabler_import_pairing(data.bytes, data.length, origin)
                         : ARMSX3_PAIRING_IMPORT_INVALID;
  NSString* title = NSLocalizedString(@"Pairing File", @"Alert title: built-in JIT pairing file");
  NSString* message = nil;
  switch (result) {
    case ARMSX3_PAIRING_IMPORT_OK:
      message = NSLocalizedString(@"Imported. With LocalDevVPN on, XeniOS turns on JIT by itself "
                                  @"the next time it starts.",
                                  @"Alert message: pairing file imported");
      break;
    case ARMSX3_PAIRING_IMPORT_LOCKDOWN:
      message = NSLocalizedString(@"This is a lockdown pairing file. Built-in JIT needs a Remote "
                                  @"Pairing file (with public_key, private_key and identifier), "
                                  @"like the one SideStore or StikDebug uses.",
                                  @"Alert message: wrong kind of pairing file");
      break;
    case ARMSX3_PAIRING_IMPORT_WRITE_FAILED:
      message = NSLocalizedString(@"The pairing file couldn't be saved.",
                                  @"Alert message: pairing file save failed");
      break;
    default:
      message = NSLocalizedString(@"This isn't a Remote Pairing file.",
                                  @"Alert message: invalid pairing file");
      break;
  }
  PresentMessage(presenter, title, message);
  if (done) {
    done();
  }
}

void XeBuiltInJITPresentPairingImport(UIViewController* presenter, void (^done)(void)) {
  NSMutableArray<UTType*>* types = [NSMutableArray arrayWithObject:UTTypePropertyList];
  if (UTType* sidestore = [UTType typeWithIdentifier:@"org.sidestore.mobiledevicepairing"]) {
    [types addObject:sidestore];
  }
  if (UTType* by_extension = [UTType typeWithFilenameExtension:@"mobiledevicepairing"]) {
    [types addObject:by_extension];
  }
  [types addObject:UTTypeData];
  UIDocumentPickerViewController* picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
  XeBuiltInJITPairingPickerDelegate* delegate = [[XeBuiltInJITPairingPickerDelegate alloc] init];
  delegate.presenter = presenter;
  delegate.done = done;
  picker.delegate = delegate;
  // The picker keeps its delegate weakly: tie the delegate's life to the picker.
  objc_setAssociatedObject(picker, @selector(presenter), delegate, OBJC_ASSOCIATION_RETAIN);
  [delegate release];
  [presenter presentViewController:picker animated:YES completion:nil];
  [picker release];
}

void XeBuiltInJITConfirmRemovePairing(UIViewController* presenter, void (^done)(void)) {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:NSLocalizedString(@"Remove Pairing File?",
                                                 @"Alert title: remove built-in JIT pairing")
                       message:NSLocalizedString(@"XeniOS won't turn on JIT by itself until you "
                                                 @"import one again.",
                                                 @"Alert message: remove built-in JIT pairing")
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Alert button")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  void (^done_copy)(void) = [[done copy] autorelease];
  [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Remove", @"Alert button")
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction* __unused action) {
                                            armsx3_jit_enabler_remove_pairing();
                                            if (done_copy) {
                                              done_copy();
                                            }
                                          }]];
  [presenter presentViewController:alert animated:YES completion:nil];
}

void XeBuiltInJITRunSetupCheck(UIViewController* presenter) {
  RunDiskImageOperation(presenter, ARMSX3_JIT_DDI_OP_CHECK,
                        NSLocalizedString(@"Test JIT Setup", @"Alert title: built-in JIT check"));
}

void XeBuiltInJITRunMountDiskImage(UIViewController* presenter) {
  RunDiskImageOperation(presenter, ARMSX3_JIT_DDI_OP_MOUNT,
                        NSLocalizedString(@"Developer Disk Image",
                                          @"Alert title: built-in JIT disk image"));
}

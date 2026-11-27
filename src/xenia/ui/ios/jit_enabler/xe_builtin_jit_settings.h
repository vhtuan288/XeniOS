/**
 ******************************************************************************
 * Xenia : Xbox 360 Emulator Research Project                                 *
 ******************************************************************************
 * Copyright 2026 Ben Vanik. All rights reserved.                             *
 * Released under the BSD license - see LICENSE in the root for more details. *
 ******************************************************************************
 */

#ifndef XENIA_UI_IOS_JIT_ENABLER_XE_BUILTIN_JIT_SETTINGS_H_
#define XENIA_UI_IOS_JIT_ENABLER_XE_BUILTIN_JIT_SETTINGS_H_

#import <UIKit/UIKit.h>

#include <string>

// Settings > System > Built-in JIT: the pairing file and the Developer Disk
// Image the built-in JIT enabler needs. Main thread only; |done| runs on the
// main thread after the settings shown may have changed.

// Whether this build carries the JIT enabler extension.
bool XeBuiltInJITAvailable();
// One line about the pairing file the next launch would use.
std::string XeBuiltInJITPairingStatusText();
// Picks a Remote Pairing file (.plist / .mobiledevicepairing) and stores it.
void XeBuiltInJITPresentPairingImport(UIViewController* presenter,
                                      void (^done)(void));
// Imports pairing file bytes that arrived another way (Open In); shows the
// result on |presenter|.
void XeBuiltInJITImportPairingData(UIViewController* presenter, NSData* data,
                                   const char* origin, void (^done)(void));
void XeBuiltInJITConfirmRemovePairing(UIViewController* presenter,
                                      void (^done)(void));
// Checks the setup (VPN, pairing, disk image) without changing anything.
void XeBuiltInJITRunSetupCheck(UIViewController* presenter);
// Downloads, if needed, and mounts the Developer Disk Image.
void XeBuiltInJITRunMountDiskImage(UIViewController* presenter);

#endif  // XENIA_UI_IOS_JIT_ENABLER_XE_BUILTIN_JIT_SETTINGS_H_

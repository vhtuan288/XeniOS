/**
 ******************************************************************************
 * Xenia : Xbox 360 Emulator Research Project                                 *
 ******************************************************************************
 * Copyright 2026 Ben Vanik. All rights reserved.                             *
 * Released under the BSD license - see LICENSE in the root for more details. *
 ******************************************************************************
 */

#ifndef XENIA_CPU_BACKEND_JIT_MEMORY_IOS_H_
#define XENIA_CPU_BACKEND_JIT_MEMORY_IOS_H_

#include <cstddef>
#include <cstdint>
#include <memory>

namespace xe::cpu::backend {

// Owns the iOS JIT mapping and its write/execute permission transitions.
// The code cache retains Edge's allocation, dispatch and unwind algorithms.
class IOSJitMemory {
 public:
  IOSJitMemory();
  ~IOSJitMemory();
  IOSJitMemory(const IOSJitMemory&) = delete;
  IOSJitMemory& operator=(const IOSJitMemory&) = delete;

  // How much address space below 8 GB is held for the code region while the
  // process loads (see jit_memory_ios.cc). The code cache's generated-code size,
  // page rounded, must fit.
  static constexpr size_t kExecuteRegionReserveSize = size_t(1) << 29;

  bool Initialize(size_t size, uint8_t*& execute_base, uint8_t*& write_base);

  // Called with true just before the app asks the JIT tool to prepare the code
  // region, which stops every thread until the tool answers, and with false
  // after. Set once, before the first Initialize.
  using ExternalPrepareHook = void (*)(bool preparing);
  static void SetExternalPrepareHook(ExternalPrepareHook hook);

  // The built-in JIT enabler: an app extension that attaches a debugger to
  // this process over the device's own loopback, writes one byte at each
  // 16 KB page start of the given (base, size) ranges, and detaches. Returns 1
  // when every page was prepared. Set once by the app, before the first
  // PrepareWithBuiltInHelper.
  using BuiltInPrepareFunction = int (*)(const uint64_t* ranges,
                                         uint32_t count, int32_t pid);
  static void SetBuiltInPrepareFunction(BuiltInPrepareFunction function);
  // Turns JIT on without an external tool: with TXM this prepares the whole
  // persistent code region, so NeedsAttachedTool() becomes false; without TXM
  // the attach alone leaves CS_DEBUGGED set. Blocks for the whole pass and
  // stops every thread while the helper is attached, so call it off the main
  // thread. Returns the helper's code (1 on success), 0 when there was nothing
  // to do or no helper is set, or -1 when the region could not be mapped.
  static int PrepareWithBuiltInHelper();

  // Code is packed only in the prepared persistent mapping; elsewhere every
  // function takes its own page, so precompiling a whole executable would fill
  // the cache.
  static bool PacksCode();
  // Whether a game can only start while the JIT tool is attached: before the
  // one-time prepare of the code region in this process. ToolAttached says
  // whether it still is.
  static bool NeedsAttachedTool();
  static bool ToolAttached();
  // Whether code is mapped through the JIT tool's TXM preparation (iOS 26 and
  // later on devices with TXM) rather than toggled under a debugger.
  static bool UsesTXMPreparation();
  size_t AlignOffset(size_t offset) const;
  bool BeginWrite(void* address, size_t size);
  bool EndWrite(void* address, size_t size);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// The scope must include both machine code and unwind-data writes.
class IOSJitWriteScope {
 public:
  IOSJitWriteScope(IOSJitMemory& memory, void* address, size_t size);
  ~IOSJitWriteScope();
  IOSJitWriteScope(const IOSJitWriteScope&) = delete;
  IOSJitWriteScope& operator=(const IOSJitWriteScope&) = delete;

 private:
  IOSJitMemory& memory_;
  void* address_;
  size_t size_;
};

}  // namespace xe::cpu::backend
#endif  // XENIA_CPU_BACKEND_JIT_MEMORY_IOS_H_

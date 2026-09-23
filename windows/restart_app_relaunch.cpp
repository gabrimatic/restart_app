#include "restart_app_relaunch.h"

#include <process.h>

#include <atomic>
#include <cerrno>
#include <memory>
#include <new>

namespace restart_app {
namespace {

std::atomic<bool> restart_pending{false};

uintptr_t begin_thread(unsigned(__stdcall *entry)(void *), void *context) {
  return _beginthreadex(nullptr, 0, entry, context, 0, nullptr);
}

void close_process_handles(HANDLE process, HANDLE thread,
                           const RestartOperations &operations) {
  if (thread != nullptr) {
    operations.close_handle(thread);
  }
  if (process != nullptr) {
    operations.close_handle(process);
  }
}

void terminate_suspended_process(HANDLE process, HANDLE thread,
                                 const RestartOperations &operations) {
  if (process != nullptr && !operations.terminate_process(process, 1)) {
    OutputDebugStringW(L"restart_app: failed to terminate suspended child\n");
  }
  close_process_handles(process, thread, operations);
}

struct RestartContext {
  HANDLE process;
  HANDLE thread;
  HANDLE response_event;
  RestartOperations operations;
};

unsigned __stdcall restart_worker(void *argument) {
  std::unique_ptr<RestartContext> context(
      static_cast<RestartContext *>(argument));
  const auto operations = context->operations;
  // A lost signal must not retain a suspended child or the process-wide guard
  // forever. The caller owns a different event handle, so timeout cleanup can
  // safely finish before the channel callback returns and signals its handle.
  const DWORD response_status = operations.wait(context->response_event, 5000);
  operations.close_handle(context->response_event);
  if (response_status != WAIT_OBJECT_0) {
    OutputDebugStringW(L"restart_app: response event was not signaled\n");
    terminate_suspended_process(context->process, context->thread, operations);
    cancel_restart();
    return 0;
  }

  // Let the platform message loop drain the successful response to Dart.
  operations.sleep(150);
  if (operations.resume_thread(context->thread) == static_cast<DWORD>(-1)) {
    OutputDebugStringW(L"restart_app: ResumeThread failed\n");
    terminate_suspended_process(context->process, context->thread, operations);
    cancel_restart();
    return 0;
  }

  close_process_handles(context->process, context->thread, operations);
  context.reset();
  operations.exit_process(0);
  return 0;
}

} // namespace

const RestartOperations &default_restart_operations() {
  static const RestartOperations operations = {
      CreateEventW, DuplicateHandle, begin_thread, WaitForSingleObject,
      SetEvent,     Sleep,           ResumeThread, TerminateProcess,
      CloseHandle,  ExitProcess};
  return operations;
}

bool try_begin_restart() {
  bool expected = false;
  return restart_pending.compare_exchange_strong(expected, true);
}

void cancel_restart() { restart_pending.store(false); }

bool schedule_restart(HANDLE process, HANDLE thread, HANDLE *response_event,
                      std::string *error, const RestartOperations &operations) {
  *response_event = nullptr;
  std::unique_ptr<RestartContext> context(
      new (std::nothrow) RestartContext{process, thread, nullptr, operations});
  if (!context) {
    terminate_suspended_process(process, thread, operations);
    cancel_restart();
    *error = "Could not allocate the application relaunch context";
    return false;
  }

  HANDLE signal_event = operations.create_event(nullptr, TRUE, FALSE, nullptr);
  if (signal_event == nullptr) {
    const DWORD code = GetLastError();
    terminate_suspended_process(process, thread, operations);
    cancel_restart();
    *error = "Could not schedule the application relaunch (event " +
             std::to_string(code) + ")";
    return false;
  }
  if (!operations.duplicate_handle(
          GetCurrentProcess(), signal_event, GetCurrentProcess(),
          &context->response_event, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
    const DWORD code = GetLastError();
    operations.close_handle(signal_event);
    terminate_suspended_process(process, thread, operations);
    cancel_restart();
    *error = "Could not schedule the application relaunch (event handle " +
             std::to_string(code) + ")";
    return false;
  }

  // _beginthreadex has an explicit failure result and does not introduce the
  // throwing detach operation of a temporary std::thread. Ownership transfers
  // only on success; the worker may start immediately and owns its context.
  const uintptr_t worker =
      operations.begin_thread(restart_worker, context.get());
  if (worker == 0) {
    const int code = errno;
    operations.close_handle(context->response_event);
    operations.close_handle(signal_event);
    terminate_suspended_process(process, thread, operations);
    cancel_restart();
    *error = "Could not schedule the application relaunch (thread " +
             std::to_string(code) + ")";
    return false;
  }
  context.release();
  operations.close_handle(reinterpret_cast<HANDLE>(worker));
  *response_event = signal_event;
  return true;
}

bool signal_restart(HANDLE response_event,
                    const RestartOperations &operations) {
  const bool signaled = operations.set_event(response_event) != FALSE;
  operations.close_handle(response_event);
  if (!signaled) {
    // The worker's bounded wait owns cleanup. Never touch its context or child
    // handles here, since it may already have completed timeout cleanup.
    OutputDebugStringW(L"restart_app: failed to signal response event\n");
  }
  return signaled;
}

} // namespace restart_app

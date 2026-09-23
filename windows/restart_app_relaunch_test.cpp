#include "restart_app_relaunch.h"

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>
#include <unordered_set>

namespace {

enum class Failure {
  kNone,
  kEvent,
  kDuplicate,
  kThread,
  kSignal,
  kWait,
  kResume
};

Failure failure = Failure::kNone;
std::mutex handles_mutex;
std::unordered_set<HANDLE> handles;
std::atomic<int> terminations{0};
std::atomic<int> resumes{0};
std::atomic<int> exits{0};
std::atomic<bool> response_sent{false};
HANDLE worker = nullptr;

void check(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::abort();
  }
}

void track(HANDLE handle) {
  std::lock_guard<std::mutex> lock(handles_mutex);
  check(handles.insert(handle).second, "a live handle was reused");
}

HANDLE WINAPI create_event(LPSECURITY_ATTRIBUTES attributes, BOOL manual_reset,
                           BOOL initial_state, LPCWSTR name) {
  if (failure == Failure::kEvent) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return nullptr;
  }
  HANDLE event = CreateEventW(attributes, manual_reset, initial_state, name);
  check(event != nullptr, "native event creation failed");
  track(event);
  return event;
}

BOOL WINAPI duplicate_handle(HANDLE source_process, HANDLE source,
                             HANDLE target_process, LPHANDLE target,
                             DWORD access, BOOL inherit, DWORD options) {
  if (failure == Failure::kDuplicate) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return FALSE;
  }
  BOOL result = DuplicateHandle(source_process, source, target_process, target,
                                access, inherit, options);
  check(result != FALSE, "native handle duplication failed");
  track(*target);
  return result;
}

uintptr_t begin_thread(unsigned(__stdcall *entry)(void *), void *context) {
  if (failure == Failure::kThread) {
    errno = EAGAIN;
    return 0;
  }
  const uintptr_t handle =
      restart_app::default_restart_operations().begin_thread(entry, context);
  check(handle != 0, "native worker creation failed");
  HANDLE thread = reinterpret_cast<HANDLE>(handle);
  check(DuplicateHandle(GetCurrentProcess(), thread, GetCurrentProcess(),
                        &worker, 0, FALSE, DUPLICATE_SAME_ACCESS) != FALSE,
        "could not retain the test worker handle");
  track(thread);
  return handle;
}

DWORD WINAPI wait(HANDLE handle, DWORD milliseconds) {
  check(milliseconds > 0 && milliseconds <= 5000,
        "the response wait must have a finite bound");
  if (failure == Failure::kWait) {
    SetLastError(ERROR_INVALID_HANDLE);
    return WAIT_FAILED;
  }
  return WaitForSingleObject(handle, milliseconds);
}

BOOL WINAPI set_event(HANDLE handle) {
  check(response_sent.load(), "event was signaled before the channel response");
  if (failure == Failure::kSignal) {
    SetLastError(ERROR_INVALID_HANDLE);
    return FALSE;
  }
  return SetEvent(handle);
}

DWORD WINAPI resume_thread(HANDLE handle) {
  check(response_sent.load(), "child resumed before the channel response");
  ++resumes;
  if (failure == Failure::kResume) {
    SetLastError(ERROR_INVALID_HANDLE);
    return static_cast<DWORD>(-1);
  }
  return ResumeThread(handle);
}

BOOL WINAPI terminate_process(HANDLE process, UINT code) {
  ++terminations;
  return TerminateProcess(process, code);
}

BOOL WINAPI close_handle(HANDLE handle) {
  {
    std::lock_guard<std::mutex> lock(handles_mutex);
    check(handles.erase(handle) == 1,
          "an unowned handle was closed or a handle was closed twice");
  }
  return CloseHandle(handle);
}

void WINAPI exit_process(UINT) { ++exits; }

void verify(Failure injected_failure) {
  failure = injected_failure;
  terminations = 0;
  resumes = 0;
  exits = 0;
  response_sent = false;
  worker = nullptr;
  check(restart_app::try_begin_restart(),
        "previous failure retained the guard");
  check(!restart_app::try_begin_restart(),
        "concurrent request acquired the guard");

  wchar_t executable[32768];
  check(GetModuleFileNameW(nullptr, executable, 32768) != 0,
        "could not resolve test executable");
  std::wstring command = L"\"" + std::wstring(executable) + L"\" --child";
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child = {};
  check(CreateProcessW(executable, &command[0], nullptr, nullptr, FALSE,
                       CREATE_SUSPENDED, nullptr, nullptr, &startup,
                       &child) != FALSE,
        "could not create a real suspended child");
  track(child.hProcess);
  track(child.hThread);
  HANDLE child_observer = nullptr;
  check(DuplicateHandle(GetCurrentProcess(), child.hProcess,
                        GetCurrentProcess(), &child_observer, 0, FALSE,
                        DUPLICATE_SAME_ACCESS) != FALSE,
        "could not observe child termination");

  auto operations = restart_app::default_restart_operations();
  operations.create_event = create_event;
  operations.duplicate_handle = duplicate_handle;
  operations.begin_thread = begin_thread;
  operations.wait = wait;
  operations.set_event = set_event;
  operations.resume_thread = resume_thread;
  operations.terminate_process = terminate_process;
  operations.close_handle = close_handle;
  operations.exit_process = exit_process;

  HANDLE response_event = nullptr;
  std::string error;
  const bool scheduled = restart_app::schedule_restart(
      child.hProcess, child.hThread, &response_event, &error, operations);
  const bool preflight_failure = failure == Failure::kEvent ||
                                 failure == Failure::kDuplicate ||
                                 failure == Failure::kThread;
  check(scheduled != preflight_failure, "wrong scheduling outcome");
  if (scheduled) {
    if (failure == Failure::kNone) {
      Sleep(30);
      check(resumes == 0, "worker did not wait for the response event");
      check(!restart_app::try_begin_restart(), "scheduled restart lost guard");
    }
    if (failure == Failure::kWait) {
      // Exercise the ownership race: let the worker close its event and child
      // before the caller accesses its distinct signal event handle.
      check(WaitForSingleObject(worker, 7000) == WAIT_OBJECT_0,
            "failed worker did not finish before late signal");
    }
    response_sent = true;
    const bool signaled =
        restart_app::signal_restart(response_event, operations);
    check(signaled == (failure != Failure::kSignal), "wrong signaling outcome");
    check(WaitForSingleObject(worker, 7000) == WAIT_OBJECT_0,
          "worker did not complete within the bounded wait");
    CloseHandle(worker);
  } else {
    check(!error.empty(), "scheduling failure did not explain the error");
    check(response_event == nullptr,
          "failed scheduling retained a signal event");
  }

  check(WaitForSingleObject(child_observer, 7000) == WAIT_OBJECT_0,
        "a suspended child was left behind");
  CloseHandle(child_observer);
  if (failure == Failure::kNone) {
    check(terminations == 0 && resumes == 1 && exits == 1,
          "successful restart did not resume exactly once and request exit");
    check(!restart_app::try_begin_restart(),
          "successful restart released guard");
    restart_app::cancel_restart();
  } else {
    check(
        terminations == 1 && exits == 0,
        "failure did not kill exactly one child and preserve the old process");
    check(resumes == (failure == Failure::kResume ? 1 : 0),
          "failure resumed a child unexpectedly");
    check(restart_app::try_begin_restart(),
          "failure did not reset pending guard");
    restart_app::cancel_restart();
  }
  check(handles.empty(), "a native handle leaked");
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--child") {
    return 0;
  }
  for (Failure injected_failure :
       {Failure::kEvent, Failure::kDuplicate, Failure::kThread,
        Failure::kSignal, Failure::kWait, Failure::kResume, Failure::kNone}) {
    verify(injected_failure);
  }
  std::puts(
      "PASS: native restart concurrency, response gating, event, duplicate, "
      "thread, signal timeout, wait, resume, and child cleanup");
  return 0;
}

#ifndef FLUTTER_PLUGIN_RESTART_APP_RELAUNCH_H_
#define FLUTTER_PLUGIN_RESTART_APP_RELAUNCH_H_

#include <windows.h>

#include <cstdint>
#include <string>

namespace restart_app {

// Keep OS operations at the scheduling boundary so native tests can exercise
// failures that are not safe to trigger in a running Flutter application.
struct RestartOperations {
  decltype(&CreateEventW) create_event;
  decltype(&DuplicateHandle) duplicate_handle;
  uintptr_t (*begin_thread)(unsigned(__stdcall *entry)(void *), void *context);
  decltype(&WaitForSingleObject) wait;
  decltype(&SetEvent) set_event;
  decltype(&Sleep) sleep;
  decltype(&ResumeThread) resume_thread;
  decltype(&TerminateProcess) terminate_process;
  decltype(&CloseHandle) close_handle;
  decltype(&ExitProcess) exit_process;
};

const RestartOperations &default_restart_operations();

// Shared across all plugin instances and engines in the current process.
bool try_begin_restart();
void cancel_restart();

// Takes ownership of both suspended-child handles, including on failure.
// On success, the caller owns the returned response event and must signal it
// only after sending the channel response. The worker owns a separate handle.
bool schedule_restart(
    HANDLE process, HANDLE thread, HANDLE *response_event, std::string *error,
    const RestartOperations &operations = default_restart_operations());
bool signal_restart(HANDLE response_event, const RestartOperations &operations =
                                               default_restart_operations());

} // namespace restart_app

#endif // FLUTTER_PLUGIN_RESTART_APP_RELAUNCH_H_

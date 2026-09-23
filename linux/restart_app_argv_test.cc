#include "restart_app_argv.h"

#include <assert.h>
#include <string.h>

#include <iostream>

int main() {
  // The caller-provided array intentionally has no trailing null entry. The
  // argc bound must be sufficient for a safe copy.
  char app[] = "restart-proof";
  char argument[] = "--run-id=bounded";
  char *input[] = {app, argument};

  char **copy = restart_app_copy_argv(2, input);
  assert(copy != nullptr);
  assert(strcmp(copy[0], app) == 0);
  assert(strcmp(copy[1], argument) == 0);
  assert(copy[2] == nullptr);
  restart_app_free_argv(copy);

  // Replacing the stored vector must release the old allocation before
  // keeping the new bounded copy.
  char replacement[] = "--replacement";
  char *replacement_input[] = {app, replacement, nullptr};
  char **stored = nullptr;
  assert(restart_app_replace_argv(&stored, 2, input));
  assert(stored != nullptr);
  assert(restart_app_replace_argv(&stored, 2, replacement_input));
  assert(strcmp(stored[1], replacement) == 0);

  // Invalid input must not produce a partially initialized vector.
  assert(restart_app_replace_argv(&stored, 0, input));
  assert(stored == nullptr);
  assert(restart_app_copy_argv(2, nullptr) == nullptr);

  std::cout << "restart_app Linux argv regression tests passed\n";
  return 0;
}

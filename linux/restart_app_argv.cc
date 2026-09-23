#include "restart_app_argv.h"

#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <limits>

char **restart_app_copy_argv(int argc, char **argv) {
  if (argc <= 0 || argv == nullptr) {
    return nullptr;
  }

  const size_t count = static_cast<size_t>(argc);
  if (count > (std::numeric_limits<size_t>::max() / sizeof(char *)) - 1) {
    return nullptr;
  }

  char **copy = static_cast<char **>(std::calloc(count + 1, sizeof(char *)));
  if (copy == nullptr) {
    return nullptr;
  }

  for (size_t index = 0; index < count; ++index) {
    const char *value = argv[index] == nullptr ? "" : argv[index];
    const size_t length = std::strlen(value);
    copy[index] = static_cast<char *>(std::malloc(length + 1));
    if (copy[index] == nullptr) {
      restart_app_free_argv(copy);
      return nullptr;
    }
    std::memcpy(copy[index], value, length + 1);
  }

  return copy;
}

void restart_app_free_argv(char **argv) {
  if (argv == nullptr) {
    return;
  }

  for (char **entry = argv; *entry != nullptr; ++entry) {
    std::free(*entry);
  }
  std::free(argv);
}

bool restart_app_replace_argv(char ***stored, int argc, char **argv) {
  if (stored == nullptr) {
    return false;
  }
  if (argc <= 0 || argv == nullptr) {
    restart_app_free_argv(*stored);
    *stored = nullptr;
    return true;
  }

  char **copy = restart_app_copy_argv(argc, argv);
  if (copy == nullptr) {
    return false;
  }

  restart_app_free_argv(*stored);
  *stored = copy;
  return true;
}

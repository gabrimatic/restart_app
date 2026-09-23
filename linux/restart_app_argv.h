#ifndef RESTART_APP_LINUX_RESTART_APP_ARGV_H_
#define RESTART_APP_LINUX_RESTART_APP_ARGV_H_

// Returns a newly allocated, null-terminated copy of exactly |argc| entries
// from |argv|. The returned vector is owned by the caller and must be released
// with restart_app_free_argv(). A null or non-positive input returns nullptr.
char **restart_app_copy_argv(int argc, char **argv);

// Releases a vector returned by restart_app_copy_argv().
void restart_app_free_argv(char **argv);

// Replaces the vector owned by |stored|. Invalid input clears the existing
// vector. Allocation failure leaves the existing vector untouched and returns
// false.
bool restart_app_replace_argv(char ***stored, int argc, char **argv);

#endif // RESTART_APP_LINUX_RESTART_APP_ARGV_H_

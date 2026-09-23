cmake_minimum_required(VERSION 3.14)
project(restart_app_native_tests LANGUAGES CXX)

enable_testing()
add_executable(restart_app_relaunch_test
  ../restart_app_relaunch.cpp
  ../restart_app_relaunch_test.cpp
)
target_compile_features(restart_app_relaunch_test PRIVATE cxx_std_14)
if(MSVC)
  target_compile_options(restart_app_relaunch_test PRIVATE /W4 /WX /EHsc)
endif()
add_test(NAME restart_app_relaunch_test COMMAND restart_app_relaunch_test)
set_tests_properties(restart_app_relaunch_test PROPERTIES TIMEOUT 60)

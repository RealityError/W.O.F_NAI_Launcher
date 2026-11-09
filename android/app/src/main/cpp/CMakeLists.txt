cmake_minimum_required(VERSION 3.22.1)

project(node_runtime_jni)

# JNI glue that embeds the nodejs-mobile Node.js runtime (libnode.so) and
# bridges its stdio pipes to the Flutter MethodChannel. Keep this file in sync
# with android/app/src/main/cpp/node/include (Node headers extracted from the
# nodejs-mobile release zip, see docs/android-port.md).
add_library(node_runtime_jni SHARED node_runtime_jni.cpp)

# Node 24 headers (v8/cppgc) require C++20.
target_compile_features(node_runtime_jni PRIVATE cxx_std_20)

target_include_directories(node_runtime_jni PRIVATE ${CMAKE_SOURCE_DIR}/node/include/node)

add_library(libnode SHARED IMPORTED)
set_target_properties(
    libnode
    PROPERTIES IMPORTED_LOCATION
    ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libnode.so
)

find_library(log-lib log)

target_link_libraries(node_runtime_jni libnode ${log-lib})

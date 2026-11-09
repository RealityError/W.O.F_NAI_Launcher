// JNI glue for the embedded Node.js runtime on Android.
//
// Node.js is started with node::Start() on a dedicated thread. Its stdio file
// descriptors are redirected to pipes so the Flutter side can exchange the
// newline-delimited JSON protocol used by the desktop host.mjs over a
// MethodChannel instead of Process.stdin/stdout.
#include <jni.h>
#include <android/log.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "node.h"

namespace {

constexpr const char* kTag = "WofNodeRuntime";

JavaVM* g_vm = nullptr;
jobject g_callback = nullptr;
int g_stdin_write = -1;
int g_stdout_read = -1;
int g_stderr_read = -1;
bool g_started = false;
std::string g_script;
std::mutex g_write_mutex;
pthread_t g_node_thread{};
pthread_t g_stdout_thread{};
pthread_t g_stderr_thread{};

struct PipeReader {
  int fd;
  const char* stream;
};

void emitEvent(JNIEnv* env, const char* stream, const std::string& line) {
  if (g_callback == nullptr) return;
  jclass cls = env->GetObjectClass(g_callback);
  if (cls == nullptr) return;
  jmethodID method =
      env->GetMethodID(cls, "onOutput", "(Ljava/lang/String;Ljava/lang/String;)V");
  if (method != nullptr) {
    jstring javaStream = env->NewStringUTF(stream);
    jstring javaLine = env->NewStringUTF(line.c_str());
    env->CallVoidMethod(g_callback, method, javaStream, javaLine);
    env->DeleteLocalRef(javaStream);
    env->DeleteLocalRef(javaLine);
  }
  env->DeleteLocalRef(cls);
}

void emitExit(JNIEnv* env, int code) {
  if (g_callback == nullptr) return;
  jclass cls = env->GetObjectClass(g_callback);
  if (cls == nullptr) return;
  jmethodID method = env->GetMethodID(cls, "onExit", "(I)V");
  if (method != nullptr) env->CallVoidMethod(g_callback, method, code);
  env->DeleteLocalRef(cls);
}

void* readLoop(void* raw) {
  auto* reader = static_cast<PipeReader*>(raw);
  JNIEnv* env = nullptr;
  if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
    delete reader;
    return nullptr;
  }
  std::string pending;
  char buffer[4096];
  for (;;) {
    const ssize_t count = read(reader->fd, buffer, sizeof(buffer));
    if (count <= 0) break;
    pending.append(buffer, static_cast<size_t>(count));
    for (;;) {
      const size_t newline = pending.find('\n');
      if (newline == std::string::npos) break;
      std::string line = pending.substr(0, newline);
      pending.erase(0, newline + 1);
      if (!line.empty() && line.back() == '\r') line.pop_back();
      emitEvent(env, reader->stream, line);
    }
  }
  if (!pending.empty()) emitEvent(env, reader->stream, pending);
  g_vm->DetachCurrentThread();
  delete reader;
  return nullptr;
}

void* nodeThread(void* /*raw*/) {
  std::vector<char> script(g_script.begin(), g_script.end());
  script.push_back('\0');
  char arg0[] = "node";
  char* argv[2] = {arg0, script.data()};
  const int code = node::Start(2, argv);
  JNIEnv* env = nullptr;
  if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) env = nullptr;
  }
  if (env != nullptr) emitExit(env, code);
  __android_log_print(ANDROID_LOG_INFO, kTag, "node runtime exited: %d", code);
  return reinterpret_cast<void*>(static_cast<intptr_t>(code));
}

bool makePipe(int fds[2]) {
  if (pipe(fds) != 0) return false;
#ifdef F_SETPIPE_SZ
  // Large enough for a burst of protocol lines without blocking Node.
  fcntl(fds[1], F_SETPIPE_SZ, 1 << 20);
#endif
  return true;
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_wof_nai_1launcher_NodeRuntimeBridge_nativeStart(
    JNIEnv* env, jobject /*thiz*/, jstring scriptPath, jstring cwd,
    jobject callback) {
  if (g_started) return JNI_FALSE;
  if (env->GetJavaVM(&g_vm) != JNI_OK) return JNI_FALSE;
  if (g_callback != nullptr) {
    env->DeleteGlobalRef(g_callback);
    g_callback = nullptr;
  }
  g_callback = env->NewGlobalRef(callback);
  if (g_callback == nullptr) return JNI_FALSE;

  const char* scriptChars = env->GetStringUTFChars(scriptPath, nullptr);
  g_script = scriptChars == nullptr ? "" : scriptChars;
  env->ReleaseStringUTFChars(scriptPath, scriptChars);

  const char* cwdChars = env->GetStringUTFChars(cwd, nullptr);
  if (cwdChars != nullptr) {
    const std::string cwdText(cwdChars);
    // host.mjs recycles sessions in place because libnode cannot start twice
    // in one process; this env gate keeps the desktop single-init behaviour.
    setenv("NAI_HOST_REINIT", "1", 1);
    const std::string home = cwdText.substr(0, cwdText.find_last_of('/'));
    if (!home.empty()) {
      setenv("HOME", home.c_str(), 1);
      setenv("TMPDIR", home.c_str(), 1);
    }
    const char* currentPath = getenv("PATH");
    const std::string path =
        std::string("/system/bin:/system/xbin:/product/bin:/vendor/bin") +
        (currentPath != nullptr && *currentPath ? std::string(":") + currentPath
                                                : std::string());
    setenv("PATH", path.c_str(), 1);
    if (chdir(cwdChars) != 0) {
      __android_log_print(ANDROID_LOG_ERROR, kTag, "chdir failed: %s", cwdChars);
    }
    env->ReleaseStringUTFChars(cwd, cwdChars);
  }

  int stdinPipe[2];
  int stdoutPipe[2];
  int stderrPipe[2];
  if (!makePipe(stdinPipe) || !makePipe(stdoutPipe) || !makePipe(stderrPipe)) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "pipe creation failed");
    return JNI_FALSE;
  }

  // Node owns fd 0/1/2; the Flutter side keeps the other ends.
  dup2(stdinPipe[0], STDIN_FILENO);
  dup2(stdoutPipe[1], STDOUT_FILENO);
  dup2(stderrPipe[1], STDERR_FILENO);
  close(stdinPipe[0]);
  close(stdoutPipe[1]);
  close(stderrPipe[1]);

  g_stdin_write = stdinPipe[1];
  g_stdout_read = stdoutPipe[0];
  g_stderr_read = stderrPipe[0];

  g_started = true;
  auto* stdoutReader = new PipeReader{g_stdout_read, "stdout"};
  auto* stderrReader = new PipeReader{g_stderr_read, "stderr"};
  pthread_create(&g_stdout_thread, nullptr, readLoop, stdoutReader);
  pthread_create(&g_stderr_thread, nullptr, readLoop, stderrReader);
  pthread_create(&g_node_thread, nullptr, nodeThread, nullptr);
  return JNI_TRUE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_wof_nai_1launcher_NodeRuntimeBridge_nativeWriteStdin(
    JNIEnv* env, jobject /*thiz*/, jbyteArray data) {
  if (g_stdin_write < 0) return 0;
  const jsize length = env->GetArrayLength(data);
  std::vector<char> buffer(static_cast<size_t>(length));
  env->GetByteArrayRegion(data, 0, length,
                          reinterpret_cast<jbyte*>(buffer.data()));
  std::lock_guard<std::mutex> guard(g_write_mutex);
  const ssize_t written = write(g_stdin_write, buffer.data(), buffer.size());
  return static_cast<jint>(written);
}

extern "C" JNIEXPORT void JNICALL
Java_com_wof_nai_1launcher_NodeRuntimeBridge_nativeStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
  if (g_stdin_write >= 0) {
    // EOF makes host.mjs close its session; node::Start then returns.
    close(g_stdin_write);
    g_stdin_write = -1;
  }
  if (g_node_thread != 0) {
    pthread_join(g_node_thread, nullptr);
    g_node_thread = 0;
  }
  // With Node gone the read ends are the last owners of the write ends.
  close(STDIN_FILENO);
  close(STDOUT_FILENO);
  close(STDERR_FILENO);
  if (g_stdout_thread != 0) {
    pthread_join(g_stdout_thread, nullptr);
    g_stdout_thread = 0;
  }
  if (g_stderr_thread != 0) {
    pthread_join(g_stderr_thread, nullptr);
    g_stderr_thread = 0;
  }
  g_stdout_read = -1;
  g_stderr_read = -1;
  g_started = false;
}

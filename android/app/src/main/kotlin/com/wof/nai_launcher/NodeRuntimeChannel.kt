package com.wof.nai_launcher

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between the embedded Node.js runtime (libnode.so + node_runtime_jni)
 * and Dart. The desktop build runs host.mjs as a child process and talks to it
 * over stdin/stdout; Android cannot spawn executables, so the same protocol is
 * carried over this MethodChannel and the JNI glue's stdio pipes.
 */
object NodeRuntimeChannel {
    private const val TAG = "WofNodeRuntime"
    private const val CHANNEL = "com.nailauncher/node_runtime"

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result -> handle(call, result) }
        channel = methodChannel
        NodeRuntimeBridge.callback = NodeRuntimeBridge.Callback { type, payload ->
            mainHandler.post {
                channel?.invokeMethod(
                    "event",
                    mapOf("type" to type, "payload" to payload),
                )
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val scriptPath = call.argument<String>("scriptPath")
                val workingDirectory = call.argument<String>("workingDirectory")
                if (scriptPath.isNullOrBlank() || workingDirectory.isNullOrBlank()) {
                    result.error("bad_args", "scriptPath and workingDirectory are required", null)
                    return
                }
                try {
                    result.success(
                        NodeRuntimeBridge.start(scriptPath, workingDirectory),
                    )
                } catch (error: Throwable) {
                    Log.e(TAG, "node runtime failed to start", error)
                    result.error("start_failed", error.message ?: error.toString(), null)
                }
            }
            "writeStdin" -> {
                val data = call.argument<String>("data")
                if (data == null) {
                    result.error("bad_args", "data is required", null)
                    return
                }
                result.success(NodeRuntimeBridge.writeStdin(data))
            }
            "stop" -> {
                NodeRuntimeBridge.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}

/**
 * Thin Kotlin facade over the JNI glue. Keep the JNI-visible method names in
 * sync with node_runtime_jni.cpp.
 */
object NodeRuntimeBridge {
    init {
        System.loadLibrary("node_runtime_jni")
    }

    private external fun nativeStart(
        scriptPath: String,
        workingDirectory: String,
        callback: Callback,
    ): Boolean
    private external fun nativeWriteStdin(data: ByteArray): Int
    private external fun nativeStop()

    /** Implemented in JNI; receives every line produced by Node's stdout/stderr. */
    internal class Callback(val emit: (String, String) -> Unit) {
        @Suppress("UNUSED")
        fun onOutput(stream: String, line: String) {
            emit(stream, line)
        }

        @Suppress("UNUSED")
        fun onExit(code: Int) {
            emit("exit", code.toString())
        }
    }

    internal var callback: Callback? = null

    fun start(scriptPath: String, workingDirectory: String): Boolean {
        val active = callback ?: return false
        return nativeStart(scriptPath, workingDirectory, active)
    }

    fun writeStdin(data: String): Int = nativeWriteStdin(data.toByteArray(Charsets.UTF_8))

    fun stop() = nativeStop()
}

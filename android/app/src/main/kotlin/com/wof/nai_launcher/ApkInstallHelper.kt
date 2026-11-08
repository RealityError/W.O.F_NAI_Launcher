package com.wof.nai_launcher

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * G17: Android 应用内 APK 下载后的安装桥（`com.nailauncher/apk_install`）。
 *
 * Dart 侧（`AndroidUpdateService`）把 APK 下载到 cache 后调用这里：
 *  - `supportedAbis` 返回设备 ABI，用于从 Release 资产里选对应的 APK；
 *  - `installApk` 通过已有的 `${applicationId}.fileprovider` 把 cache 里的
 *    文件转成 content:// URI，再以 `application/vnd.android.package-archive`
 *    拉起系统安装器；
 *  - `canRequestPackageInstalls` / `openUnknownSourcesSettings` 处理
 *    Android 8+ 的「安装未知应用」授权。
 *
 * 只使用 android.* / androidx.core API；调用入口：
 * 在 MainActivity.configureFlutterEngine() 里调用
 * `ApkInstallHelper.register(flutterEngine, this)`。
 */
object ApkInstallHelper {
    private const val TAG = "WofApkInstall"
    private const val CHANNEL = "com.nailauncher/apk_install"
    private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
    private const val APK_MIME_TYPE = "application/vnd.android.package-archive"

    /**
     * 注册 MethodChannel。必须在主线程、Activity 可用时调用（
     * MainActivity.configureFlutterEngine 正好满足）。
     */
    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        installApk(activity, path, result)
                    }
                    "canRequestPackageInstalls" ->
                        result.success(canRequestPackageInstalls(activity))
                    "openUnknownSourcesSettings" -> {
                        openUnknownSourcesSettings(activity)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(
        activity: Activity,
        path: String?,
        result: MethodChannel.Result,
    ) {
        if (path.isNullOrBlank()) {
            result.success(failure("missing path"))
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.success(failure("apk file does not exist"))
            return
        }
        // Only serve files this app downloaded into its own cache directory.
        if (!isInsideCache(activity, file)) {
            result.success(failure("apk is outside the app cache directory"))
            return
        }
        if (!canRequestPackageInstalls(activity)) {
            openUnknownSourcesSettings(activity)
            result.success(mapOf("status" to "permission_required"))
            return
        }
        try {
            val authority = activity.packageName + FILE_PROVIDER_SUFFIX
            val uri = FileProvider.getUriForFile(activity, authority, file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME_TYPE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success(mapOf("status" to "launched"))
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "No package installer activity", error)
            result.success(failure("no package installer activity"))
        } catch (error: Exception) {
            Log.w(TAG, "Failed to launch package installer", error)
            result.success(failure(error.message ?: "failed to launch installer"))
        }
    }

    private fun canRequestPackageInstalls(activity: Activity): Boolean {
        // Below Android 8 the unknown-sources switch is global, not per-app.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return activity.packageManager.canRequestPackageInstalls()
    }

    private fun openUnknownSourcesSettings(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(intent)
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "No unknown-sources settings activity", error)
        }
    }

    private fun isInsideCache(activity: Activity, file: File): Boolean {
        return try {
            // java.nio.file is API 26+; minSdk is 24, so compare canonical strings.
            val cacheRoot = activity.cacheDir.canonicalPath + File.separator
            file.canonicalPath.startsWith(cacheRoot)
        } catch (error: Exception) {
            Log.w(TAG, "Failed to resolve apk path", error)
            false
        }
    }

    private fun failure(message: String): Map<String, String> {
        return mapOf("status" to "failed", "message" to message)
    }
}

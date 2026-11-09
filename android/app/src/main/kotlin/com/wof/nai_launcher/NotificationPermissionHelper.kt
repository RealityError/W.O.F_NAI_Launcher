package com.wof.nai_launcher

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android 13+ 通知运行时权限桥（`com.nailauncher/notifications`）。
 *
 * Android 13（API 33）起 `POST_NOTIFICATIONS` 变成运行时权限，新装应用默认
 * 没有授权，后台生成的进度/完成通知不可见。Dart 侧
 * （`NotificationPermissionService`）只在真正开始生成时调用这里：
 *  - `areNotificationsEnabled` 返回系统当前是否允许本应用发通知；
 *  - `requestNotifications` 在 API 33+ 弹系统权限框，结果经
 *    `MainActivity.onRequestPermissionsResult` 回传；API < 33 没有运行时权限，
 *    直接返回 true；
 *  - `openNotificationSettings` 跳本应用的通知设置页。
 *
 * 只使用 android.* / androidx.core API。调用入口：在
 * `MainActivity.configureFlutterEngine()` 里调用
 * `NotificationPermissionHelper.register(flutterEngine, this)`。
 */
object NotificationPermissionHelper {
    private const val TAG = "WofNotifications"
    private const val CHANNEL = "com.nailauncher/notifications"

    /** 通知权限请求码；与其它 Activity 结果互不冲突即可。 */
    const val REQUEST_POST_NOTIFICATIONS = 43011

    private val pendingResults = mutableListOf<MethodChannel.Result>()

    /**
     * 注册 MethodChannel。必须在主线程、Activity 可用时调用
     * （MainActivity.configureFlutterEngine 正好满足）。
     */
    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "areNotificationsEnabled" ->
                        result.success(areNotificationsEnabled(activity))
                    "requestNotifications" -> requestNotifications(activity, result)
                    "openNotificationSettings" ->
                        openNotificationSettings(activity, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** 系统是否允许本应用发通知（各 API 级别都可用）。 */
    private fun areNotificationsEnabled(activity: Activity): Boolean {
        return try {
            NotificationManagerCompat.from(activity).areNotificationsEnabled()
        } catch (error: Exception) {
            // 读取失败时按可用处理，避免误报权限问题打断生成。
            Log.w(TAG, "Failed to read notification enabled state", error)
            true
        }
    }

    /**
     * 申请通知权限：API 33+ 弹系统权限框，结果回调统一在这里完成；API < 33
     * 视为已授权，立即返回 true。系统弹窗只能有一个，重复调用先挂起，等同一个
     * 结果一起回传。
     */
    private fun requestNotifications(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (areNotificationsEnabled(activity)) {
            // 已经允许（例如用户手动在设置里打开）时不再弹框。
            result.success(true)
            return
        }
        pendingResults.add(result)
        if (pendingResults.size > 1) {
            // 已有系统弹窗在等结果，复用同一次回调。
            return
        }
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_POST_NOTIFICATIONS
            )
        } catch (error: Exception) {
            Log.w(TAG, "Failed to request notification permission", error)
            pendingResults.remove(result)
            result.success(false)
        }
    }

    /**
     * `MainActivity.onRequestPermissionsResult` 转发过来；返回 true 表示这个
     * 请求码属于通知权限并已消费。
     */
    fun handleRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val results = pendingResults.toList()
        pendingResults.clear()
        for (result in results) {
            result.success(granted)
        }
        return true
    }

    /** 打开本应用的通知设置页（API 26+ 通知详情，更早版本退回应用详情）。 */
    private fun openNotificationSettings(
        activity: Activity,
        result: MethodChannel.Result,
    ) {
        val packageUri = Uri.parse("package:${activity.packageName}")
        val primary = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
        }
        primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(primary)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            // 个别 ROM 没有通知详情页，退回应用详情页。
            Log.w(TAG, "No notification settings activity", error)
            openAppDetailsSettings(activity, packageUri, result)
        } catch (error: Exception) {
            Log.w(TAG, "Failed to open notification settings", error)
            result.success(false)
        }
    }

    private fun openAppDetailsSettings(
        activity: Activity,
        packageUri: Uri,
        result: MethodChannel.Result,
    ) {
        val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(fallback)
            result.success(true)
        } catch (inner: Exception) {
            Log.w(TAG, "No app details settings activity", inner)
            result.success(false)
        }
    }
}

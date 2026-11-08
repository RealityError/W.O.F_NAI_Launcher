package com.wof.nai_launcher

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Android 前台服务：生成任务切到后台时保活，并在完成/失败时发通知（G10）。
 *
 * Dart 通过 `com.nailauncher/generation` 的 `start` / `update` / `stop` 控制：
 * - 常驻通知使用固定 channel `wof_generation`，文案由 Dart 传入；
 * - 进度 0..1 可选，不传就不画进度条；
 * - 停止时移除常驻通知，再发一条普通完成通知，点击回到 MainActivity。
 *
 * 所有入口都 try/catch，通知权限被拒（Android 13+）时静默降级，不崩溃。
 */
class GenerationForegroundService : Service() {
    companion object {
        private const val TAG = "WofGenerationService"

        /** 与 Dart 侧 `com.nailauncher/generation` 约定的 channel id。 */
        const val CHANNEL_ID = "wof_generation"

        private const val CHANNEL_NAME = "后台生成"
        private const val CHANNEL_DESCRIPTION = "生成任务在后台运行时的进度与完成通知"
        private const val DEFAULT_TITLE = "后台生成"

        private const val PROGRESS_NOTIFICATION_ID = 43001
        private const val COMPLETION_NOTIFICATION_ID = 43002

        private const val ACTION_START =
            "com.wof.nai_launcher.action.GENERATION_SERVICE_START"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS = "progress"

        @Volatile
        private var running: GenerationForegroundService? = null

        /** 启动/更新常驻前台通知。 */
        fun start(context: Context, title: String?, text: String?) {
            startOrUpdate(context, title, text, null)
        }

        /**
         * 更新常驻通知文案/进度。服务已在运行时直接改通知（避免后台再走
         * startForegroundService 被系统限制）；否则按启动处理。
         */
        fun update(context: Context, title: String?, text: String?, progress: Double?) {
            val service = running
            if (service != null) {
                service.postProgress(title ?: DEFAULT_TITLE, text ?: "", progress)
                return
            }
            startOrUpdate(context, title, text, progress)
        }

        /** 停止前台服务并补发一条完成通知。 */
        fun stop(context: Context, title: String?, text: String?) {
            val service = running
            if (service != null) {
                try {
                    ServiceCompat.stopForeground(
                        service,
                        ServiceCompat.STOP_FOREGROUND_REMOVE
                    )
                } catch (error: Exception) {
                    Log.w(TAG, "stopForeground failed", error)
                }
                try {
                    service.stopSelf()
                } catch (error: Exception) {
                    Log.w(TAG, "stopSelf failed", error)
                }
            } else {
                // start 与 stop 紧邻时服务可能还没创建，兜底把启动请求停掉。
                try {
                    context.stopService(
                        Intent(context, GenerationForegroundService::class.java)
                    )
                } catch (error: Exception) {
                    Log.w(TAG, "stopService failed", error)
                }
            }
            showCompletion(context, title ?: "生成完成", text ?: "")
        }

        private fun startOrUpdate(
            context: Context,
            title: String?,
            text: String?,
            progress: Double?,
        ) {
            try {
                ensureChannel(context)
                val intent = Intent(
                    context,
                    GenerationForegroundService::class.java
                ).apply {
                    action = ACTION_START
                    putExtra(EXTRA_TITLE, title ?: DEFAULT_TITLE)
                    putExtra(EXTRA_TEXT, text ?: "")
                    if (progress != null) putExtra(EXTRA_PROGRESS, progress)
                }
                ContextCompat.startForegroundService(context, intent)
            } catch (error: Exception) {
                // 权限/后台启动限制都不应把异常抛回 Dart。
                Log.w(TAG, "Failed to start generation foreground service", error)
            }
        }

        @SuppressLint("MissingPermission") // 通知权限被拒时 notify 静默丢弃。
        private fun showCompletion(context: Context, title: String, text: String) {
            try {
                ensureChannel(context)
                NotificationManagerCompat.from(context).notify(
                    COMPLETION_NOTIFICATION_ID,
                    buildCompletionNotification(context, title, text)
                )
            } catch (error: Exception) {
                Log.w(TAG, "Failed to post completion notification", error)
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            try {
                val manager = context.getSystemService(
                    Context.NOTIFICATION_SERVICE
                ) as? NotificationManager ?: return
                if (manager.getNotificationChannel(CHANNEL_ID) != null) return
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = CHANNEL_DESCRIPTION
                    setShowBadge(false)
                    setSound(null, null)
                }
                manager.createNotificationChannel(channel)
            } catch (error: Exception) {
                Log.w(TAG, "Failed to create notification channel", error)
            }
        }

        private fun launchAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun smallIcon(context: Context): Int {
            val icon = context.applicationInfo.icon
            return if (icon != 0) icon else android.R.drawable.ic_dialog_info
        }

        private fun buildProgressNotification(
            context: Context,
            title: String,
            text: String,
            progress: Double?,
        ): Notification {
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(smallIcon(context))
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(launchAppIntent(context))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            if (progress != null && progress.isFinite()) {
                val clamped = progress.coerceIn(0.0, 1.0)
                builder.setProgress(100, (clamped * 100).toInt(), false)
            }
            return builder.build()
        }

        private fun buildCompletionNotification(
            context: Context,
            title: String,
            text: String,
        ): Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIcon(context))
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(launchAppIntent(context))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        running = this
        ensureChannel(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY
        val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
        val progress = if (intent.hasExtra(EXTRA_PROGRESS)) {
            intent.getDoubleExtra(EXTRA_PROGRESS, 0.0)
        } else {
            null
        }
        try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(
                this,
                PROGRESS_NOTIFICATION_ID,
                buildProgressNotification(this, title, text, progress),
                type
            )
        } catch (error: Exception) {
            // 通知权限缺失、后台启动限制等：不要崩溃，直接结束本次服务。
            Log.w(TAG, "startForeground failed", error)
            stopSelf()
            return START_NOT_STICKY
        }
        running = this
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (running === this) running = null
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (error: Exception) {
            Log.w(TAG, "stopForeground failed in onDestroy", error)
        }
        super.onDestroy()
    }

    @SuppressLint("MissingPermission") // 通知权限被拒时 notify 静默丢弃。
    private fun postProgress(title: String, text: String, progress: Double?) {
        try {
            NotificationManagerCompat.from(this).notify(
                PROGRESS_NOTIFICATION_ID,
                buildProgressNotification(this, title, text, progress)
            )
        } catch (error: Exception) {
            Log.w(TAG, "Failed to update generation notification", error)
        }
    }
}

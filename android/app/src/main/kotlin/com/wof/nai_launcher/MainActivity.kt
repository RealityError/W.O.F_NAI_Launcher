package com.wof.nai_launcher

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Android intent bridge for the desktop file actions that used to spawn
 * explorer.exe / `open`. Dart talks to it through the
 * `com.nailauncher/platform` MethodChannel.
 *
 * Only plain android.* / androidx.core APIs are used so the module keeps
 * compiling without extra Gradle dependencies.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "WofPlatformChannel"
        private const val CHANNEL = "com.nailauncher/platform"
        private const val GENERATION_CHANNEL = "com.nailauncher/generation"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
        private const val ALBUM_DIRECTORY = "W.O.F NAI Studio"
        private const val DIRECTORY_MIME_TYPE = "vnd.android.document/directory"
        private const val GET_SHARED_IMAGE_METHOD = "getSharedImage"
        private const val SHARE_RECEIVED_METHOD = "shareImageReceived"
        private const val INCOMING_SHARE_DIRECTORY = "incoming_shares"
    }

    private var platformChannel: MethodChannel? = null

    /** Cache path of an ACTION_SEND image not yet consumed by Dart. */
    private var pendingSharedImage: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    /**
     * G18: 通知权限的系统回调。委托给 `NotificationPermissionHelper` 完成挂起
     * 的 `requestNotifications` 调用；其它 requestCode 保持默认行为。
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        NotificationPermissionHelper.handleRequestPermissionsResult(
            requestCode,
            grantResults
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // G17: in-app APK update channel (`com.nailauncher/apk_install`).
        ApkInstallHelper.register(flutterEngine, this)
        // G18: Android 13+ notification runtime permission channel.
        NotificationPermissionHelper.register(flutterEngine, this)
        // NAI Agent: embedded Node.js runtime (libnode.so) bridge.
        NodeRuntimeChannel.register(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> openFile(call, result)
                "shareFile" -> shareFile(call, result)
                "saveImageToMediaStore" -> saveImageToMediaStore(call, result)
                "openDirectory" -> openDirectory(call, result)
                "getSystemProxy" -> getSystemProxy(result)
                GET_SHARED_IMAGE_METHOD -> getSharedImage(result)
                else -> result.notImplemented()
            }
        }
        platformChannel = channel
        // A share that started the app may arrive before Dart registers its
        // handler; it stays pending for the startup `getSharedImage` poll.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GENERATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleGenerationServiceCall(call, result)
        }
    }

    /**
     * G10: keeps generation alive in the background through a dataSync
     * foreground service and posts the completion notification.
     */
    private fun handleGenerationServiceCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    GenerationForegroundService.start(
                        this,
                        call.argument<String>("title"),
                        call.argument<String>("text")
                    )
                    result.success(true)
                }
                "update" -> {
                    GenerationForegroundService.update(
                        this,
                        call.argument<String>("title"),
                        call.argument<String>("text"),
                        progressArgument(call.argument<Any>("progress"))
                    )
                    result.success(true)
                }
                "stop" -> {
                    GenerationForegroundService.stop(
                        this,
                        call.argument<String>("title"),
                        call.argument<String>("text")
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // Never leak a native exception into Dart; report a boolean instead.
            Log.w(TAG, "Generation service call failed: ${call.method}", error)
            result.success(false)
        }
    }

    private fun progressArgument(value: Any?): Double? {
        val number = value as? Number ?: return null
        val progress = number.toDouble()
        return if (progress.isFinite()) progress else null
    }

    /**
     * Android "share image to this app" (G16). Copies the shared content uri
     * into the app cache, keeps it pending, then signals Dart if it is running.
     */
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) {
            return
        }
        val isImage = intent.type?.startsWith("image/") == true
        if (!isImage) {
            return
        }
        val uri = sharedImageUri(intent)
        if (uri == null) {
            Log.w(TAG, "ACTION_SEND without an image stream")
            return
        }
        // Mark the intent consumed so activity recreation cannot re-import it.
        intent.action = null
        val cachedPath = copySharedImageToCache(uri)
        if (cachedPath == null) {
            Log.w(TAG, "Failed to import shared image: $uri")
            return
        }
        pendingSharedImage = cachedPath
        signalShareReceived()
    }

    @Suppress("DEPRECATION")
    private fun sharedImageUri(intent: Intent): Uri? {
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (stream != null) {
            return stream
        }
        val clip = intent.clipData
        if (clip != null && clip.itemCount > 0) {
            return clip.getItemAt(0).uri
        }
        return null
    }

    private fun copySharedImageToCache(uri: Uri): String? {
        val type = try {
            contentResolver.getType(uri)
        } catch (error: Exception) {
            Log.w(TAG, "Failed to resolve shared image type", error)
            null
        }
        if (type != null && !type.startsWith("image/")) {
            Log.w(TAG, "Shared content is not an image: $type")
            return null
        }
        val displayName = querySharedDisplayName(uri) ?: "shared.png"
        val directory = File(cacheDir, INCOMING_SHARE_DIRECTORY).apply { mkdirs() }
        val target = File(
            directory,
            "${System.currentTimeMillis()}_${sanitizeSharedFileName(displayName)}"
        )
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source ->
                FileOutputStream(target).use { output -> source.copyTo(output) }
            }
            if (!target.exists() || target.length() == 0L) {
                target.delete()
                null
            } else {
                target.absolutePath
            }
        } catch (error: Exception) {
            Log.w(TAG, "Failed to copy shared image into cache", error)
            target.delete()
            null
        }
    }

    private fun querySharedDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor: Cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: uri.lastPathSegment
        } catch (error: Exception) {
            Log.w(TAG, "Failed to query shared image name", error)
            uri.lastPathSegment
        }
    }

    private fun sanitizeSharedFileName(name: String): String {
        val base = name.substringAfterLast('/').substringAfterLast('\\')
        val sanitized = base.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_")
        if (sanitized.isBlank() || sanitized.trim('_').isEmpty()) {
            return "shared.png"
        }
        return if (sanitized.contains('.')) sanitized else "$sanitized.png"
    }

    /** Tells Dart that an image was shared while the app was already running. */
    private fun signalShareReceived() {
        val channel = platformChannel ?: return
        try {
            channel.invokeMethod(SHARE_RECEIVED_METHOD, null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // Dart consumes the image through getSharedImage.
                }

                override fun error(code: String, message: String?, details: Any?) {
                    Log.w(TAG, "Dart share handler error: $code $message")
                }

                override fun notImplemented() {
                    // Dart is not ready yet; the startup/resume poll picks it up.
                }
            })
        } catch (error: Exception) {
            Log.w(TAG, "Failed to signal shared image to Dart", error)
        }
    }

    /** Dart pulls the pending shared image; consuming it clears it natively. */
    private fun getSharedImage(result: MethodChannel.Result) {
        val path = pendingSharedImage
        pendingSharedImage = null
        result.success(path)
    }

    /** ACTION_VIEW on a FileProvider content uri, for images / videos / zips. */
    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.success(false)
            return
        }
        val uri = resolveContentUri(path)
        if (uri == null) {
            result.success(false)
            return
        }
        val mimeType = call.argument<String>("mimeType") ?: mimeTypeForPath(path)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        result.success(startSafely(intent))
    }

    /** ACTION_SEND share sheet for a single file. */
    private fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.success(false)
            return
        }
        val uri = resolveContentUri(path)
        if (uri == null) {
            result.success(false)
            return
        }
        val mimeType = call.argument<String>("mimeType") ?: mimeTypeForPath(path)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(contentResolver, "file", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        result.success(startSafely(Intent.createChooser(send, null)))
    }

    /**
     * Copies the file into MediaStore Pictures/W.O.F NAI Studio (Android 10+)
     * without any storage permission and returns the content uri.
     */
    private fun saveImageToMediaStore(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.success(null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.w(TAG, "MediaStore album save requires Android 10 (API 29)")
            result.success(null)
            return
        }
        val displayName = call.argument<String>("displayName")?.takeIf { it.isNotBlank() }
            ?: File(path).name
        // Copying a generated PNG can take a moment; keep it off the UI thread
        // and answer on the platform thread as MethodChannel requires.
        Thread {
            val uri = try {
                copyToMediaStore(File(path), displayName)
            } catch (error: Exception) {
                Log.e(TAG, "Failed to save image to MediaStore", error)
                null
            }
            Handler(Looper.getMainLooper()).post { result.success(uri?.toString()) }
        }.start()
    }

    /** Best-effort "open the folder"; Android file managers do not target app dirs. */
    private fun openDirectory(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.success(false)
            return
        }
        val directory = File(path)
        if (!directory.exists() || !directory.isDirectory) {
            result.success(false)
            return
        }
        val authority = "$packageName$FILE_PROVIDER_SUFFIX"
        val openedDirectly = try {
            val uri = FileProvider.getUriForFile(this, authority, directory)
            startSafely(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, DIRECTORY_MIME_TYPE)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
        } catch (error: IllegalArgumentException) {
            false
        }
        if (openedDirectly) {
            result.success(true)
            return
        }
        // Fall back to the system file manager home; it cannot show an
        // app-private directory but at least gives the user storage access.
        val filesIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_APP_FILES)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        result.success(startSafely(filesIntent))
    }

    /**
     * Returns the Android global HTTP proxy as "host:port", or null when unset.
     *
     * Flutter's dart:io never consults the Android system proxy, so the Dart
     * side reads it once at startup and installs HttpOverrides itself.
     */
    private fun getSystemProxy(result: MethodChannel.Result) {
        val raw = try {
            android.provider.Settings.Global.getString(
                contentResolver,
                android.provider.Settings.Global.HTTP_PROXY
            )
        } catch (error: Exception) {
            Log.w(TAG, "Failed to read global http_proxy", error)
            null
        }
        val normalized = raw?.trim().orEmpty()
        result.success(
            if (
                normalized.isEmpty() ||
                normalized == ":0" ||
                normalized.equals("null", ignoreCase = true)
            ) {
                null
            } else {
                normalized
            }
        )
    }

    private fun resolveContentUri(path: String): Uri? {
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            Log.w(TAG, "File does not exist: $path")
            return null
        }
        val authority = "$packageName$FILE_PROVIDER_SUFFIX"
        try {
            return FileProvider.getUriForFile(this, authority, file)
        } catch (error: IllegalArgumentException) {
            // App-private documents dir (path_provider app_flutter) is not one
            // of the FileProvider roots, so share a cache copy instead.
            val cached = copyToSharedCache(file) ?: return null
            return try {
                FileProvider.getUriForFile(this, authority, cached)
            } catch (inner: IllegalArgumentException) {
                Log.w(TAG, "Failed to expose cached file: ${cached.path}", inner)
                null
            }
        }
    }

    private fun copyToSharedCache(source: File): File? {
        return try {
            val directory = File(cacheDir, "shared_files").apply { mkdirs() }
            val target = File(directory, "${System.currentTimeMillis()}_${source.name}")
            FileInputStream(source).use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            target
        } catch (error: Exception) {
            Log.w(TAG, "Failed to cache shared file: ${source.path}", error)
            null
        }
    }

    @SuppressLint("NewApi") // Callers gate on Build.VERSION.SDK_INT >= Q.
    private fun copyToMediaStore(source: File, displayName: String): Uri? {
        if (!source.exists() || !source.isFile) {
            return null
        }
        // Idempotent per display name: a repeated "save to album" on the same
        // gallery file must not create duplicate Pictures entries.
        findExistingMediaStoreImage(displayName)?.let { existing ->
            Log.i(TAG, "Album image already exists: $displayName")
            return existing
        }
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeTypeForPath(source.name))
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/$ALBUM_DIRECTORY"
            )
            put(MediaStore.Images.Media.IS_PENDING, Integer.valueOf(1))
        }
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = resolver.insert(collection, values) ?: return null
        try {
            val output = resolver.openOutputStream(uri)
            if (output == null) {
                resolver.delete(uri, null, null)
                return null
            }
            output.use { stream ->
                FileInputStream(source).use { input -> input.copyTo(stream) }
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, Integer.valueOf(0))
            resolver.update(uri, values, null, null)
            return uri
        } catch (error: Exception) {
            Log.e(TAG, "Failed to write MediaStore image: ${source.path}", error)
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {
                // Nothing else to clean up.
            }
            return null
        }
    }

    @SuppressLint("NewApi") // Only called from the Q+ MediaStore path.
    private fun findExistingMediaStoreImage(displayName: String): Uri? {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val selection =
            "${MediaStore.Images.Media.DISPLAY_NAME}=? AND " +
                "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?"
        val selectionArgs = arrayOf(
            displayName,
            "${Environment.DIRECTORY_PICTURES}/$ALBUM_DIRECTORY%"
        )
        return try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.Images.Media._ID),
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    null
                } else {
                    val id = cursor.getLong(0)
                    ContentUris.withAppendedId(collection, id)
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "Failed to query album for $displayName", error)
            null
        }
    }

    private fun startSafely(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "No activity for ${intent.action}", error)
            false
        } catch (error: Exception) {
            Log.w(TAG, "Failed to start ${intent.action}", error)
            false
        }
    }

    private fun mimeTypeForPath(path: String): String {
        return when (path.substringAfterLast('.', "").lowercase()) {
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "bmp" -> "image/bmp"
            "mp4" -> "video/mp4"
            "webm" -> "video/webm"
            "zip" -> "application/zip"
            "json" -> "application/json"
            else -> "*/*"
        }
    }
}

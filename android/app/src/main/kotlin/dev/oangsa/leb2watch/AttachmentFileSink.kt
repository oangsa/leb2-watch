package dev.oangsa.leb2watch

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale

private const val channelName = "dev.oangsa.leb2watch/attachment-file-sink"
private const val saveMethod = "saveAttachment"
private const val unsupportedStorageCode = "UNSUPPORTED_ANDROID_PUBLIC_STORAGE"
private const val saveFailedCode = "SAVE_FAILED"
private const val saveFailedMessage = "The file could not be saved."
private const val publicFolderName = "Downloads/LEB2"

/** Writes completed attachment bytes into the user's public Downloads folder. */
fun configureAttachmentFileSink(
    flutterEngine: FlutterEngine,
    applicationContext: Context,
) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        .setMethodCallHandler { call, result ->
            if (call.method != saveMethod) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val fileName = call.argument<String>("fileName")
            val bytes = call.argument<ByteArray>("bytes")
            val contentType = call.argument<String>("contentType")
            val openAfterSave = call.argument<Boolean>("openAfterSave") ?: true
            if (fileName.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
                result.error(saveFailedCode, saveFailedMessage, null)
                return@setMethodCallHandler
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.error(unsupportedStorageCode, saveFailedMessage, null)
                return@setMethodCallHandler
            }

            try {
                result.success(
                    saveAttachment(
                        applicationContext,
                        fileName,
                        bytes,
                        contentType,
                        openAfterSave,
                    ),
                )
            } catch (_: Exception) {
                result.error(saveFailedCode, saveFailedMessage, null)
            }
        }
}

private fun saveAttachment(
    context: Context,
    requestedName: String,
    bytes: ByteArray,
    requestedContentType: String?,
    openAfterSave: Boolean,
): String {
    val fileName = sanitizeFileName(requestedName) ?: throw IOException()
    val resolver = context.contentResolver
    val displayName = nextAvailableName(resolver, fileName)
    val type = mimeType(requestedContentType, displayName)
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, displayName)
        put(MediaStore.Downloads.MIME_TYPE, type)
        put(
            MediaStore.Downloads.RELATIVE_PATH,
            "${Environment.DIRECTORY_DOWNLOADS}/LEB2",
        )
        put(MediaStore.Downloads.IS_PENDING, 1)
    }
    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        ?: throw IOException()

    return try {
        resolver.openOutputStream(uri)?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IOException()

        val complete = ContentValues().apply {
            put(MediaStore.Downloads.IS_PENDING, 0)
        }
        if (resolver.update(uri, complete, null, null) != 1) {
            throw IOException()
        }
        if (openAfterSave) {
            openAttachment(context, uri, type)
        }
        "$publicFolderName/$displayName"
    } catch (error: Exception) {
        resolver.delete(uri, null, null)
        throw error
    }
}

/** Opens a published attachment when the device has a compatible viewer. */
private fun openAttachment(context: Context, uri: Uri, type: String) {
    try {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, type)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    } catch (_: Exception) {
        // The file remains saved when opening is unavailable or rejected.
    }
}

private fun nextAvailableName(
    resolver: ContentResolver,
    requestedName: String,
): String {
    if (!contains(resolver, requestedName)) {
        return requestedName
    }

    val dot = requestedName.lastIndexOf('.')
    val stem = if (dot > 0) requestedName.substring(0, dot) else requestedName
    val extension = if (dot > 0) requestedName.substring(dot) else ""
    for (suffix in 2..999) {
        val candidate = "$stem ($suffix)$extension"
        if (!contains(resolver, candidate)) {
            return candidate
        }
    }
    return "$stem (${System.currentTimeMillis()})$extension"
}

private fun contains(resolver: ContentResolver, displayName: String): Boolean {
    val projection = arrayOf(MediaStore.MediaColumns._ID)
    val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
        "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
        "${MediaStore.MediaColumns.IS_PENDING} = 0"
    val arguments = arrayOf("${Environment.DIRECTORY_DOWNLOADS}/LEB2", displayName)
    return resolver.query(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        projection,
        selection,
        arguments,
        null,
    ).use { cursor -> cursor?.moveToFirst() == true }
}

private fun mimeType(contentType: String?, fileName: String): String {
    val normalizedContentType = contentType
        ?.substringBefore(';')
        ?.trim()
        ?.lowercase(Locale.ROOT)
    if (normalizedContentType != null &&
        normalizedContentType.matches(Regex("^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$"))
    ) {
        return normalizedContentType
    }
    val extension = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        ?: "application/octet-stream"
}

private fun sanitizeFileName(value: String): String? {
    val sanitized = value
        .replace('/', '_')
        .replace('\\', '_')
        .filterNot { character -> character.code < 32 || character.code == 127 }
        .trim()
        .trimStart('.')
        .take(180)
    return sanitized.ifEmpty { null }
}

package dev.oangsa.leb2watch

import android.content.Context
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

private const val channelName = "dev.oangsa.leb2watch.test/workmanager-runtime"
private const val periodicSyncUniqueWorkName = "dev.oangsa.leb2watch.periodic-sync.v1"
private const val generationTagPrefix = "dev.oangsa.leb2watch.periodic-sync.generation-v1."

fun configureDebugWorkmanagerRuntimeInspector(
    flutterEngine: FlutterEngine,
    applicationContext: Context,
) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        .setMethodCallHandler { call, result ->
            if (call.method != "snapshot" || call.arguments != null) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val records = WorkManager.getInstance(applicationContext)
                    .getWorkInfosForUniqueWork(periodicSyncUniqueWorkName)
                    .get(2, TimeUnit.SECONDS)
                    .filter { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING }
                    .map(::sanitizedRecord)
                result.success(mapOf("records" to records))
            } catch (_: Exception) {
                result.error("unavailable", "WorkManager inspection unavailable.", null)
            }
        }
}

private fun sanitizedRecord(info: WorkInfo): Map<String, Any> = mapOf(
    "state" to info.state.name,
    "networkType" to info.constraints.requiredNetworkType.name,
    "periodic" to (info.periodicityInfo != null),
    "generationTags" to info.tags
        .filter { it.startsWith(generationTagPrefix) }
        .sorted(),
)

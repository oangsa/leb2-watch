package dev.oangsa.leb2watch

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val channelName = "dev.oangsa.leb2watch/battery-optimization"

/**
 * Exposes Android's battery-optimization allowlist to Dart.
 *
 * Periodic WorkManager runs are deferred aggressively while the app is
 * optimized, which is what makes background sync lag far behind its cadence.
 */
fun configureBatteryOptimizationExemption(
    flutterEngine: FlutterEngine,
    activity: Activity,
) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        .setMethodCallHandler { call, result ->
            when (call.method) {
                "isExempt" -> result.success(isExempt(activity))
                "requestExemption" -> {
                    if (isExempt(activity)) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    // The system dialog reports its outcome only through a
                    // later status read, so this reports submission and Dart
                    // re-reads `isExempt` when the app resumes.
                    val launched = launchExemptionRequest(activity)
                    result.success(launched)
                }
                "openSettings" -> result.success(openBatterySettings(activity))
                else -> result.notImplemented()
            }
        }
}

private fun isExempt(context: Context): Boolean {
    val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        ?: return false
    return power.isIgnoringBatteryOptimizations(context.packageName)
}

private fun launchExemptionRequest(activity: Activity): Boolean = try {
    activity.startActivity(
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        },
    )
    true
} catch (_: Exception) {
    openBatterySettings(activity)
}

private fun openBatterySettings(activity: Activity): Boolean = try {
    activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    true
} catch (_: Exception) {
    false
}

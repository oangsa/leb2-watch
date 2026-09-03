package dev.oangsa.leb2watch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureDebugWorkmanagerRuntimeInspector(flutterEngine, applicationContext)
        configureBatteryOptimizationExemption(flutterEngine, this)
        configureAttachmentFileSink(flutterEngine, applicationContext)
    }
}

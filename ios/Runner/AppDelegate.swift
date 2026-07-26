import BackgroundTasks
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

private enum BackgroundRefreshConstants {
  static let taskIdentifier = "dev.oangsa.leb2watch.assignment-refresh"
  static let methodChannel = "dev.oangsa.leb2watch/background_refresh"
  static let earliestBeginSeconds = 15 * 60
}

final class BackgroundRefreshStatusBridge: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: BackgroundRefreshConstants.methodChannel,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(BackgroundRefreshStatusBridge(), channel: channel)
  }

  static func refreshStatusName(for status: UIBackgroundRefreshStatus) -> String {
    switch status {
    case .available:
      return "available"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getStatus" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let refreshStatus = Self.refreshStatusName(
      for: UIApplication.shared.backgroundRefreshStatus
    )
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      let pending = requests.contains {
        $0.identifier == BackgroundRefreshConstants.taskIdentifier
      }
      DispatchQueue.main.async {
        result([
          "backgroundRefreshStatus": refreshStatus,
          "pending": pending,
        ])
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: BackgroundRefreshConstants.taskIdentifier,
      frequency: NSNumber(value: BackgroundRefreshConstants.earliestBeginSeconds)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackgroundRefreshStatusBridge.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: "BackgroundRefreshStatusBridge"
      )
    )
  }
}

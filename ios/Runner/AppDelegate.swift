import BackgroundTasks
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

private enum BackgroundRefreshConstants {
  static let taskIdentifier = "dev.oangsa.leb2watch.assignment-refresh"
  static let methodChannel = "dev.oangsa.leb2watch/background_refresh"
  static let expirationMethodChannel =
    "dev.oangsa.leb2watch/background_refresh_expiration"
  static let earliestBeginSeconds = 15 * 60
}

protocol BackgroundRefreshExpirationNotifier: AnyObject {
  func notifyExpired(generation: String)
}

struct BackgroundRefreshExpirationSnapshot {
  let generation: String
  let expired: Bool
}

final class BackgroundRefreshExpirationCoordinator {
  static let shared = BackgroundRefreshExpirationCoordinator()

  private let lock = NSLock()
  private var activeGeneration: String?
  private var expired = false
  private weak var notifier: BackgroundRefreshExpirationNotifier?

  @discardableResult
  func begin(generation: String = UUID().uuidString.lowercased()) -> String {
    lock.lock()
    defer { lock.unlock() }
    activeGeneration = generation
    expired = false
    notifier = nil
    return generation
  }

  func attach(
    notifier: BackgroundRefreshExpirationNotifier
  ) -> BackgroundRefreshExpirationSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    guard let generation = activeGeneration else {
      return nil
    }
    self.notifier = notifier
    return BackgroundRefreshExpirationSnapshot(
      generation: generation,
      expired: expired
    )
  }

  @discardableResult
  func expire(generation: String) -> Bool {
    let matchingNotifier: BackgroundRefreshExpirationNotifier?
    lock.lock()
    guard activeGeneration == generation, !expired else {
      lock.unlock()
      return false
    }
    expired = true
    matchingNotifier = notifier
    lock.unlock()
    matchingNotifier?.notifyExpired(generation: generation)
    return true
  }

  @discardableResult
  func detach(generation: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard activeGeneration == generation else {
      return false
    }
    notifier = nil
    return true
  }
}

final class BackgroundRefreshExpirationChain {
  private let lock = NSLock()
  private let coordinator: BackgroundRefreshExpirationCoordinator
  private let generation: String
  private let original: () -> Void
  private var invoked = false

  init(
    coordinator: BackgroundRefreshExpirationCoordinator,
    generation: String,
    original: @escaping () -> Void
  ) {
    self.coordinator = coordinator
    self.generation = generation
    self.original = original
  }

  func invoke() {
    lock.lock()
    guard !invoked else {
      lock.unlock()
      return
    }
    invoked = true
    lock.unlock()

    coordinator.expire(generation: generation)
    original()
  }
}

final class BackgroundRefreshExpirationBridge:
  NSObject,
  FlutterPlugin,
  BackgroundRefreshExpirationNotifier
{
  private let channel: FlutterMethodChannel
  private let coordinator: BackgroundRefreshExpirationCoordinator

  init(
    channel: FlutterMethodChannel,
    coordinator: BackgroundRefreshExpirationCoordinator =
      BackgroundRefreshExpirationCoordinator.shared
  ) {
    self.channel = channel
    self.coordinator = coordinator
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: BackgroundRefreshConstants.expirationMethodChannel,
      binaryMessenger: registrar.messenger()
    )
    let instance = BackgroundRefreshExpirationBridge(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "attach":
      guard let snapshot = coordinator.attach(notifier: self) else {
        result(
          FlutterError(
            code: "background_refresh_not_active",
            message: "No active background refresh generation.",
            details: nil
          )
        )
        return
      }
      result([
        "generation": snapshot.generation,
        "expired": snapshot.expired,
      ])
    case "detach":
      guard
        let arguments = call.arguments as? [String: Any],
        let generation = arguments["generation"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_background_refresh_generation",
            message: "The background refresh generation is invalid.",
            details: nil
          )
        )
        return
      }
      coordinator.detach(generation: generation)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func notifyExpired(generation: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod(
        "expired",
        arguments: ["generation": generation]
      )
    }
  }
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
      BackgroundRefreshExpirationBridge.register(
        with: registry.registrar(
          forPlugin: "BackgroundRefreshExpirationBridge"
        )
      )
    }
    let expirationCoordinator = BackgroundRefreshExpirationCoordinator.shared
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: BackgroundRefreshConstants.taskIdentifier,
      using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      let generation = expirationCoordinator.begin()
      WorkmanagerPlugin.handlePeriodicTask(
        identifier: BackgroundRefreshConstants.taskIdentifier,
        task: refreshTask,
        earliestBeginInSeconds:
          Double(BackgroundRefreshConstants.earliestBeginSeconds)
      )
      guard
        let workmanagerExpirationHandler = refreshTask.expirationHandler
      else {
        expirationCoordinator.detach(generation: generation)
        refreshTask.setTaskCompleted(success: false)
        return
      }
      let expirationChain = BackgroundRefreshExpirationChain(
        coordinator: expirationCoordinator,
        generation: generation,
        original: workmanagerExpirationHandler
      )
      refreshTask.expirationHandler = expirationChain.invoke
    }
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

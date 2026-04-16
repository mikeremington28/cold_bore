import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingSharedJson: String?

  private func loadSharedJson(from url: URL) -> Bool {
    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if shouldStopAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let data = try Data(contentsOf: url)
      guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
      }
      pendingSharedJson = text
      return true
    } catch {
      return false
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Setup iCloud backup method channel safely.
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return didFinish
    }

    let icloudChannel = FlutterMethodChannel(name: "com.remington.coldbore/icloud",
                                             binaryMessenger: controller.binaryMessenger)
    let incomingShareChannel = FlutterMethodChannel(name: "com.remington.coldbore/incoming_share",
                                                    binaryMessenger: controller.binaryMessenger)

    incomingShareChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "takePendingSharedJson":
        let json = self?.pendingSharedJson
        self?.pendingSharedJson = nil
        DispatchQueue.main.async {
          result(json)
        }
      default:
        DispatchQueue.main.async {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    icloudChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "backupToiCloud":
        if let args = call.arguments as? [String: Any],
           let backupData = args["backupData"] as? String,
           let timestamp = args["timestamp"] as? String {
          CloudKitBackupHandler.shared.backupToiCloud(backupData: backupData, timestamp: timestamp) { message in
            DispatchQueue.main.async {
              if let message = message, message.hasPrefix("Backup failed:") {
                result(FlutterError(code: "ICLOUD_BACKUP_FAILED", message: message, details: nil))
              } else {
                result(message)
              }
            }
          }
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          }
        }
      case "restoreFromiCloud":
        CloudKitBackupHandler.shared.restoreFromiCloud { backupData in
          DispatchQueue.main.async {
            result(backupData)
          }
        }
      default:
        DispatchQueue.main.async {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return didFinish
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if loadSharedJson(from: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
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

    icloudChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "backupToiCloud":
        if let args = call.arguments as? [String: Any],
           let backupData = args["backupData"] as? String,
           let timestamp = args["timestamp"] as? String {
          CloudKitBackupHandler.shared.backupToiCloud(backupData: backupData, timestamp: timestamp) { message in
            DispatchQueue.main.async {
              result(message)
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
}

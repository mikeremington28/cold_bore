import Flutter
import MultipeerConnectivity
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingSharedJson: String?
  private let nearbyShareManager = NearbyShareManager()

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
    let nearbyShareChannel = FlutterMethodChannel(name: "com.remington.coldbore/nearby_share",
                            binaryMessenger: controller.binaryMessenger)
    let nearbyShareEventsChannel = FlutterMethodChannel(name: "com.remington.coldbore/nearby_share_events",
                              binaryMessenger: controller.binaryMessenger)

    nearbyShareManager.eventChannel = nearbyShareEventsChannel

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

    nearbyShareChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Nearby share manager unavailable", details: nil))
        return
      }

      switch call.method {
      case "startPresence":
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing identifier", details: nil))
          return
        }
        let displayName = (args["displayName"] as? String) ?? identifier
        self.nearbyShareManager.startPresence(identifier: identifier, displayName: displayName)
        result(nil)
      case "stopPresence":
        self.nearbyShareManager.stopPresence()
        result(nil)
      case "setSharePayload":
        let args = call.arguments as? [String: Any]
        let jsonText = args?["jsonText"] as? String
        self.nearbyShareManager.setPayload(jsonText)
        result(nil)
      case "clearSharePayload":
        self.nearbyShareManager.setPayload(nil)
        result(nil)
      case "invitePeer":
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing peer identifier", details: nil))
          return
        }
        do {
          try self.nearbyShareManager.invitePeer(identifier: identifier)
          result(nil)
        } catch {
          result(FlutterError(code: "INVITE_FAILED", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
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

private final class NearbyShareManager: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
  private let serviceType = "coldboremesh"
  var eventChannel: FlutterMethodChannel?

  private var localIdentifier = ""
  private var localDisplayName = "Cold Bore"
  private var peerID: MCPeerID?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var session: MCSession?
  private var nearbyPeers: [String: MCPeerID] = [:]
  private var nearbyNames: [String: String] = [:]
  private var payloadText: String?
  private var pendingTargetIdentifier: String?

  func startPresence(identifier: String, displayName: String) {
    let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !normalizedIdentifier.isEmpty else { return }

    if normalizedIdentifier == localIdentifier, advertiser != nil, browser != nil {
      return
    }

    stopPresence()
    localIdentifier = normalizedIdentifier
    localDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? normalizedIdentifier
      : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

    peerID = MCPeerID(displayName: normalizedIdentifier)
    guard let peerID else { return }

    let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    session.delegate = self
    self.session = session

    let advertiser = MCNearbyServiceAdvertiser(
      peer: peerID,
      discoveryInfo: ["name": localDisplayName],
      serviceType: serviceType
    )
    advertiser.delegate = self
    advertiser.startAdvertisingPeer()
    self.advertiser = advertiser

    let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
    browser.delegate = self
    browser.startBrowsingForPeers()
    self.browser = browser

    emitPeersUpdated()
  }

  func stopPresence() {
    advertiser?.stopAdvertisingPeer()
    browser?.stopBrowsingForPeers()
    session?.disconnect()
    advertiser = nil
    browser = nil
    session = nil
    peerID = nil
    nearbyPeers.removeAll()
    nearbyNames.removeAll()
    pendingTargetIdentifier = nil
    emitPeersUpdated()
  }

  func setPayload(_ jsonText: String?) {
    let trimmed = jsonText?.trimmingCharacters(in: .whitespacesAndNewlines)
    payloadText = trimmed?.isEmpty == true ? nil : trimmed
  }

  func invitePeer(identifier: String) throws {
    let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let peer = nearbyPeers[normalizedIdentifier], let session else {
      throw NSError(domain: "ColdBoreNearbyShare", code: 404, userInfo: [NSLocalizedDescriptionKey: "Nearby user not found. Make sure both phones are open in Cold Bore."])
    }
    pendingTargetIdentifier = normalizedIdentifier
    browser?.invitePeer(peer, to: session, withContext: nil, timeout: 15)
  }

  private func emit(_ method: String, arguments: Any? = nil) {
    DispatchQueue.main.async {
      self.eventChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  private func emitPeersUpdated() {
    let payload = nearbyPeers.keys.sorted().map { identifier in
      [
        "identifier": identifier,
        "displayName": nearbyNames[identifier] ?? identifier,
      ]
    }
    emit("peersUpdated", arguments: payload)
  }

  private func sendPayloadIfReady(to peer: MCPeerID) {
    guard let target = pendingTargetIdentifier,
          peer.displayName.uppercased() == target,
          let session,
          let payloadText,
          let data = payloadText.data(using: .utf8) else {
      return
    }

    do {
      try session.send(data, toPeers: [peer], with: .reliable)
      pendingTargetIdentifier = nil
      emit("payloadSent", arguments: ["identifier": peer.displayName.uppercased()])
    } catch {
      emit("payloadSendFailed", arguments: [
        "identifier": peer.displayName.uppercased(),
        "error": error.localizedDescription,
      ])
    }
  }

  func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                  didReceiveInvitationFromPeer peerID: MCPeerID,
                  withContext context: Data?,
                  invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    if session == nil, let currentPeerID = peerIDForSession() {
      let newSession = MCSession(peer: currentPeerID, securityIdentity: nil, encryptionPreference: .required)
      newSession.delegate = self
      session = newSession
    }
    invitationHandler(true, session)
  }

  func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    emit("payloadSendFailed", arguments: [
      "identifier": "",
      "error": error.localizedDescription,
    ])
  }

  func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
    let identifier = peerID.displayName.uppercased()
    guard identifier != localIdentifier else { return }
    nearbyPeers[identifier] = peerID
    let name = info?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    nearbyNames[identifier] = (name?.isEmpty == false ? name! : identifier)
    emitPeersUpdated()
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    let identifier = peerID.displayName.uppercased()
    nearbyPeers.removeValue(forKey: identifier)
    nearbyNames.removeValue(forKey: identifier)
    emitPeersUpdated()
  }

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    emit("payloadSendFailed", arguments: [
      "identifier": "",
      "error": error.localizedDescription,
    ])
  }

  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    if state == .connected {
      sendPayloadIfReady(to: peerID)
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    guard let jsonText = String(data: data, encoding: .utf8) else { return }
    emit("payloadReceived", arguments: [
      "jsonText": jsonText,
      "senderIdentifier": peerID.displayName.uppercased(),
    ])
  }

  func session(_ session: MCSession,
               didReceive stream: InputStream,
               withName streamName: String,
               fromPeer peerID: MCPeerID) {}

  func session(_ session: MCSession,
               didStartReceivingResourceWithName resourceName: String,
               fromPeer peerID: MCPeerID,
               with progress: Progress) {}

  func session(_ session: MCSession,
               didFinishReceivingResourceWithName resourceName: String,
               fromPeer peerID: MCPeerID,
               at localURL: URL?,
               withError error: Error?) {}

  func session(_ session: MCSession,
               didReceiveCertificate certificate: [Any]?,
               fromPeer peerID: MCPeerID,
               certificateHandler: @escaping (Bool) -> Void) {
    certificateHandler(true)
  }

  @available(iOS 14.0, *)
  func session(_ session: MCSession,
               didReceive message: Data,
               fromPeer peerID: MCPeerID) {
    self.session(session, didReceive: message, fromPeer: peerID)
  }

  private func peerIDForSession() -> MCPeerID? {
    if let peerID { return peerID }
    guard !localIdentifier.isEmpty else { return nil }
    let rebuilt = MCPeerID(displayName: localIdentifier)
    self.peerID = rebuilt
    return rebuilt
  }
}

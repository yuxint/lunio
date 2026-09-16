import Flutter
import UIKit
import UniformTypeIdentifiers
import WidgetKit

class SceneDelegate: FlutterSceneDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?
  private var documentPickerMode: DocumentPickerMode?
  private var nativeFilesChannel: FlutterMethodChannel?
  private var nativeNotificationSettingsChannel: FlutterMethodChannel?
  private var nativeLiveActivitiesChannel: FlutterMethodChannel?
  private var nativeWidgetsChannel: FlutterMethodChannel?

  private enum DocumentPickerMode {
    case exportJson
    case pickJson
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureNativeFilesChannelIfNeeded()
    DispatchQueue.main.async { [weak self] in
      self?.configureNativeFilesChannelIfNeeded()
      self?.configureNativeNotificationSettingsChannelIfNeeded()
      self?.configureNativeLiveActivitiesChannelIfNeeded()
      self?.configureNativeWidgetsChannelIfNeeded()
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    configureNativeFilesChannelIfNeeded()
    configureNativeNotificationSettingsChannelIfNeeded()
    configureNativeLiveActivitiesChannelIfNeeded()
    configureNativeWidgetsChannelIfNeeded()
  }

  private func configureNativeFilesChannelIfNeeded() {
    guard nativeFilesChannel == nil else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lunio/native_files",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      switch call.method {
      case "exportJsonFile":
        self?.exportJsonFile(call: call, controller: controller, result: result)
      case "pickJsonFile":
        self?.pickJsonFile(controller: controller, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativeFilesChannel = channel
  }

  private func configureNativeNotificationSettingsChannelIfNeeded() {
    guard nativeNotificationSettingsChannel == nil else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lunio/native_notification_settings",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "openNotificationSettings":
        self?.openNotificationSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativeNotificationSettingsChannel = channel
  }

  private func configureNativeLiveActivitiesChannelIfNeeded() {
    guard nativeLiveActivitiesChannel == nil else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lunio/native_live_activities",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleLiveActivityCall(call, result: result)
    }
    nativeLiveActivitiesChannel = channel
  }

  /// 停车实时活动通道分发（Dart 侧桥接 lib/core/platform/native_live_activities.dart）。
  /// 时间戳统一用毫秒 double 跨通道。iOS < 16.2（staleDate 门槛，ADR 0012）
  /// 与参数缺失一律按"未启用"回 false，Dart 侧静默降级为"只有通知"。
  private func handleLiveActivityCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 16.2, *) else {
      result(false)
      return
    }
    switch call.method {
    case "start":
      guard
        let arguments = call.arguments as? [String: Any],
        let startedAtMs = arguments["startedAtMs"] as? Double,
        let endsAtMs = arguments["endsAtMs"] as? Double
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Missing live activity timestamps",
          details: nil
        ))
        return
      }
      ParkingCountdownActivityController.start(
        startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
        endsAt: Date(timeIntervalSince1970: endsAtMs / 1000)
      ) { started in
        result(started)
      }
    case "markExpired":
      ParkingCountdownActivityController.markExpired { updated in
        result(updated)
      }
    case "stop":
      // 等全部活动确认撤场再回包：Dart 侧 await stop() 返回时岛已撤
      //（真机反馈：随即退后台时撤场半路夭折会留下残卡——现叠加后台
      // 保活根治，见 ParkingCountdownActivityController.runKeptAlive）。
      ParkingCountdownActivityController.stopAll {
        result(true)
      }
    case "status":
      ParkingCountdownActivityController.status { snapshot in
        result(snapshot)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 桌面小组件快照通道分发（Dart 侧桥接 lib/core/platform/native_widgets.dart）。
  /// 把快照 JSON 写进 App Group 共享存储（LunioWidgetSnapshotStore，ADR
  /// 0013）并请求 WidgetKit 重载时间线。iOS < 14 无 WidgetKit，按"未启用"
  /// 回 false，Dart 侧静默降级（桌面小组件缺失不影响 App 功能）。
  private func configureNativeWidgetsChannelIfNeeded() {
    guard nativeWidgetsChannel == nil else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lunio/native_widgets",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleWidgetCall(call, result: result)
    }
    nativeWidgetsChannel = channel
  }

  private func handleWidgetCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "updateSnapshot":
      guard #available(iOS 14.0, *) else {
        result(false)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let json = arguments["json"] as? String
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Missing widget snapshot json",
          details: nil
        ))
        return
      }
      let saved = LunioWidgetSnapshotStore.save(json: json)
      if saved {
        WidgetCenter.shared.reloadAllTimelines()
      }
      result(saved)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openNotificationSettings(result: @escaping FlutterResult) {
    let fallbackURL = URL(string: UIApplication.openSettingsURLString)
    guard let url = fallbackURL else {
      result(FlutterError(code: "invalid_url", message: "Unable to open app settings", details: nil))
      return
    }
    openSettingsURL(url, fallbackURL: nil, result: result)
  }

  private func openSettingsURL(_ url: URL, fallbackURL: URL?, result: @escaping FlutterResult) {
    let completion: (Bool) -> Void = { [weak self] opened in
      guard !opened, url.absoluteString != fallbackURL?.absoluteString, let fallbackURL else {
        result(opened)
        return
      }
      self?.openSettingsURL(fallbackURL, fallbackURL: nil, result: result)
    }
    if let windowScene = window?.windowScene {
      windowScene.open(url, options: nil, completionHandler: completion)
      return
    }
    UIApplication.shared.open(url, options: [:], completionHandler: completion)
  }

  private func exportJsonFile(
    call: FlutterMethodCall,
    controller: UIViewController?,
    result: @escaping FlutterResult
  ) {
    guard let controller else {
      result(FlutterError(code: "no_controller", message: "No root view controller", details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let filename = arguments["filename"] as? String,
      let content = arguments["content"] as? String
    else {
      result(FlutterError(code: "invalid_arguments", message: "Missing backup filename or content", details: nil))
      return
    }
    if documentPickerResult != nil {
      result(FlutterError(code: "picker_active", message: "A document picker is already active", details: nil))
      return
    }
    do {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
      try content.write(to: url, atomically: true, encoding: .utf8)
      documentPickerResult = result
      documentPickerMode = .exportJson
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(
          forExporting: [url],
          asCopy: true
        )
      } else {
        picker = UIDocumentPickerViewController(
          url: url,
          in: .exportToService
        )
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      controller.present(picker, animated: true)
    } catch {
      result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func pickJsonFile(controller: UIViewController?, result: @escaping FlutterResult) {
    guard let controller else {
      result(FlutterError(code: "no_controller", message: "No root view controller", details: nil))
      return
    }
    if documentPickerResult != nil {
      result(FlutterError(code: "picker_active", message: "A document picker is already active", details: nil))
      return
    }
    documentPickerResult = result
    documentPickerMode = .pickJson
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.json, UTType.plainText],
        asCopy: true
      )
    } else {
      picker = UIDocumentPickerViewController(
        documentTypes: ["public.json", "public.text"],
        in: .import
      )
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    controller.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let result = documentPickerResult else {
      return
    }
    documentPickerResult = nil
    let mode = documentPickerMode
    documentPickerMode = nil
    if mode == .exportJson {
      result(true)
      return
    }
    guard let url = urls.first else {
      result(nil)
      return
    }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      result(text)
    } catch {
      result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let mode = documentPickerMode
    documentPickerResult?(mode == .exportJson ? false : nil)
    documentPickerResult = nil
    documentPickerMode = nil
  }
}

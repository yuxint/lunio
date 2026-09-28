import Flutter
import UIKit
import UniformTypeIdentifiers
import WidgetKit

class SceneDelegate: FlutterSceneDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?
  private var documentPickerMode: DocumentPickerMode?

  /// 已挂载通道表：键 = 通道名，兼任幂等守卫与 channel 强持有（等价于旧实现
  /// 的四个逐通道属性——那些属性除幂等守卫外没有任何读者，故收编进这里）。
  private var mountedChannels: [String: FlutterMethodChannel] = [:]

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
    // scene 连接瞬间 rootViewController 尚未就绪，跳一拍主线程再挂；
    // 仍不满足前置条件时由 didBecomeActive 兜底再试（两段式重试，历史修复）。
    // 挂载时机编排只在这两处生命周期回调 + mountChannelsIfNeeded，不在各通道重复。
    DispatchQueue.main.async { [weak self] in
      self?.mountChannelsIfNeeded()
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    mountChannelsIfNeeded()
  }

  /// 四条原生通道的挂载名册：通道名 + 方法分发闭包（闭包各自 [weak self]，
  /// 与 Dart 侧桥接文件的通道名一一对应）。加第五条通道 = 这里加一行；
  /// 挂载时机、幂等守卫、channel 构造与 handler 接线全部归
  /// mountChannelsIfNeeded 独享，不再按通道复制（旧实现四份 configure
  /// 方法各抄一遍生命周期，且已出现微漂移）。
  private var channelRoster: [(name: String, handle: (FlutterMethodCall, @escaping FlutterResult) -> Void)] {
    [
      (name: "lunio/native_files", handle: { [weak self] call, result in
        self?.handleFilesCall(call, result: result)
      }),
      (name: "lunio/native_notification_settings", handle: { [weak self] call, result in
        self?.handleNotificationSettingsCall(call, result: result)
      }),
      (name: "lunio/native_live_activities", handle: { [weak self] call, result in
        self?.handleLiveActivityCall(call, result: result)
      }),
      (name: "lunio/native_widgets", handle: { [weak self] call, result in
        self?.handleWidgetCall(call, result: result)
      }),
    ]
  }

  /// 把名册里未挂载的通道全部挂上；幂等，可随生命周期反复调用。
  /// 前置条件 = window?.rootViewController 已是 FlutterViewController，不满足
  /// 时静默返回、等下一次生命周期回调再试。旧实现里 files 通道有一次
  /// willConnect 同步尝试，属历史化石（它早于重试机制诞生），本轮统一去掉：
  /// 四条通道节奏一致 = willConnect 跳一拍主线程首试 + didBecomeActive 兜底。
  private func mountChannelsIfNeeded() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    for entry in channelRoster where mountedChannels[entry.name] == nil {
      let channel = FlutterMethodChannel(
        name: entry.name,
        binaryMessenger: controller.binaryMessenger
      )
      let handle = entry.handle
      channel.setMethodCallHandler { call, result in
        handle(call, result)
      }
      mountedChannels[entry.name] = channel
    }
  }

  /// 备份导出/导入通道分发（Dart 侧桥接 lib/core/platform/native_files.dart）。
  /// 文档选择器要挂在 rootViewController 上，分发时现场取——通道能挂上即意味着
  /// controller 已就绪，这里取到 nil 只会让两个方法按约定回 no_controller 错误。
  private func handleFilesCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let controller = window?.rootViewController as? FlutterViewController
    switch call.method {
    case "exportJsonFile":
      exportJsonFile(call: call, controller: controller, result: result)
    case "pickJsonFile":
      pickJsonFile(controller: controller, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 通知设置跳转通道分发（Dart 侧桥接 lib/core/platform/native_notification_settings.dart）。
  private func handleNotificationSettingsCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "openNotificationSettings":
      openNotificationSettings(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
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

  /// 打开系统设置里本应用的通知页（Dart 侧桥接 lib/core/platform/native_notification_settings.dart），
  /// result 回传 Bool 表示是否打开成功。iOS 只有一级可开——openSettingsURLString
  /// 就是应用设置页（内含通知开关），不像 Android（MainActivity.openNotificationSettings）
  /// 的通知 action 可能被厂商 ROM 拦截、需要第二级兜底；iOS 没有第二级 URL，不做降级链。
  private func openNotificationSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(FlutterError(code: "invalid_url", message: "Unable to open app settings", details: nil))
      return
    }
    let completion: (Bool) -> Void = { opened in
      result(opened)
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

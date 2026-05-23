import Flutter
import UIKit
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureNativeFilesChannel()
  }

  private func configureNativeFilesChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lunio/native_files",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      switch call.method {
      case "shareFile":
        self?.shareFile(call: call, controller: controller, result: result)
      case "pickJsonFile":
        self?.pickJsonFile(controller: controller, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func shareFile(
    call: FlutterMethodCall,
    controller: UIViewController?,
    result: FlutterResult
  ) {
    guard let controller else {
      result(FlutterError(code: "no_controller", message: "No root view controller", details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(FlutterError(code: "invalid_arguments", message: "Missing file path", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "file_not_found", message: "Backup file not found", details: nil))
      return
    }
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(
        x: controller.view.bounds.midX,
        y: controller.view.bounds.midY,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }
    controller.present(activity, animated: true)
    result(nil)
  }

  private func pickJsonFile(controller: UIViewController?, result: @escaping FlutterResult) {
    guard let controller else {
      result(FlutterError(code: "no_controller", message: "No root view controller", details: nil))
      return
    }
    documentPickerResult = result
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
    documentPickerResult?(nil)
    documentPickerResult = nil
  }
}

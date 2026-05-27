import Flutter
import UIKit
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?
  private var documentPickerMode: DocumentPickerMode?

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
      case "exportJsonFile":
        self?.exportJsonFile(call: call, controller: controller, result: result)
      case "pickJsonFile":
        self?.pickJsonFile(controller: controller, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
      result(nil)
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
    documentPickerResult?(nil)
    documentPickerResult = nil
    documentPickerMode = nil
  }
}

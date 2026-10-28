import Flutter
import UIKit
import UniformTypeIdentifiers
import Foundation // 添加此行

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  var flutterResult: FlutterResult?
  var directoryPath: URL!

  // 定义插件通道名称
  private var directoryPicker: DirectoryPicker?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
          fatalError("rootViewController is not of type FlutterViewController")
    }

    let glassChannel = FlutterMethodChannel(name: "venera/native_glass", binaryMessenger: controller.binaryMessenger)
    glassChannel.setMethodCallHandler { call, result in
      if call.method == "isSupported" {
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      } else { result(FlutterMethodNotImplemented) }
    }
    if let registrar = registrar(forPlugin: "VeneraNativeGlass") {
      registrar.register(VeneraGlassFactory(messenger: controller.binaryMessenger), withId: "venera/native_glass_surface")
    }

    let methodChannel = FlutterMethodChannel(name: "venera/method_channel", binaryMessenger: controller.binaryMessenger)
    methodChannel.setMethodCallHandler { (call, result) in
      if call.method == "getProxy" {
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?,
          let dict = proxySettings.object(forKey: kCFNetworkProxiesHTTPProxy) as? NSDictionary,
          let host = dict.object(forKey: kCFNetworkProxiesHTTPProxy) as? String,
          let port = dict.object(forKey: kCFNetworkProxiesHTTPPort) as? Int {
          let proxyConfig = "\(host):\(port)"
          result(proxyConfig)
        } else {
          result("")
        }
      } else if call.method == "setScreenOn" {
        if let arguments = call.arguments as? Bool {
          let screenOn = arguments
          UIApplication.shared.isIdleTimerDisabled = screenOn
        }
        result(nil)
      } else if call.method == "getDirectoryPath" {
        self.flutterResult = result
        self.getDirectoryPath()
      } else if call.method == "stopAccessingSecurityScopedResource" {
        self.directoryPath?.stopAccessingSecurityScopedResource()
        self.directoryPath = nil
        result(nil)
      } else if call.method == "selectDirectory" {
        self.directoryPicker = DirectoryPicker()
        self.directoryPicker?.selectDirectory(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func getDirectoryPath() {
    let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    documentPicker.directoryURL = nil
    documentPicker.modalPresentationStyle = .formSheet

    if let rootViewController = window?.rootViewController {
      rootViewController.present(documentPicker, animated: true, completion: nil)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    self.directoryPath = urls.first
    if self.directoryPath == nil {
      flutterResult?(nil)
      return
    }

    let success = self.directoryPath.startAccessingSecurityScopedResource()

    if success {
      flutterResult?(self.directoryPath.path)
    } else {
      flutterResult?(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    flutterResult?(nil)
  }
}

private class VeneraGlassFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    VeneraGlassView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}

private class VeneraGlassView: NSObject, FlutterPlatformView {
  private let surface: UIVisualEffectView
  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?
  private var parameters: [String: Any] = [:]

  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    surface = UIVisualEffectView(frame: frame)
    channel = FlutterMethodChannel(name: "venera/native_glass/\(id)", binaryMessenger: messenger)
    super.init()
    surface.isUserInteractionEnabled = false
    surface.clipsToBounds = true
    update(args as? [String: Any] ?? [:])
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update" { self?.update(call.arguments as? [String: Any] ?? [:]); result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
    observer = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }; self.update(self.parameters)
    }
  }
  func update(_ args: [String: Any]) {
    parameters = args
    surface.layer.cornerRadius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
    let dark = args["dark"] as? Bool ?? false
    surface.overrideUserInterfaceStyle = dark ? .dark : .light
    if UIAccessibility.isReduceTransparencyEnabled {
      surface.effect = nil
      surface.backgroundColor = dark ? .secondarySystemBackground : .systemBackground
    } else if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = false
      surface.backgroundColor = .clear
      surface.effect = effect
    } else {
      surface.effect = UIBlurEffect(style: .systemMaterial)
    }
  }
  func view() -> UIView { surface }
  deinit {
    channel.setMethodCallHandler(nil)
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
  }
}

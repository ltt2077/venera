import Flutter
import UIKit
import UniformTypeIdentifiers
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  var flutterResult: FlutterResult?
  var directoryPath: URL!
  private var directoryPicker: DirectoryPicker?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let glassChannel = FlutterMethodChannel(name: "venera/native_glass", binaryMessenger: messenger)
    glassChannel.setMethodCallHandler { call, result in
      if call.method == "isSupported" {
        // UIGlassEffect ships with iOS 26+; device runtime decides.
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    // Register platform-view factory exactly once. Registering the same viewType
    // on both applicationRegistrar and registrar(forPlugin:) asserts / SIGABRT
    // at launch under Flutter's implicit-engine UIScene path.
    let glassFactory = VeneraGlassFactory(messenger: messenger)
    engineBridge.applicationRegistrar.register(
      glassFactory,
      withId: "venera/native_glass_surface"
    )

    let methodChannel = FlutterMethodChannel(name: "venera/method_channel", binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "getProxy" {
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?,
          let dict = proxySettings.object(forKey: kCFNetworkProxiesHTTPProxy) as? NSDictionary,
          let host = dict.object(forKey: kCFNetworkProxiesHTTPProxy) as? String,
          let port = dict.object(forKey: kCFNetworkProxiesHTTPPort) as? Int {
          result("\(host):\(port)")
        } else {
          result("")
        }
      } else if call.method == "setScreenOn" {
        if let arguments = call.arguments as? Bool {
          UIApplication.shared.isIdleTimerDisabled = arguments
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
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  func getDirectoryPath() {
    let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    documentPicker.directoryURL = nil
    documentPicker.modalPresentationStyle = .formSheet
    topViewController()?.present(documentPicker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    self.directoryPath = urls.first
    if self.directoryPath == nil {
      flutterResult?(nil)
      return
    }
    let success = self.directoryPath.startAccessingSecurityScopedResource()
    flutterResult?(success ? self.directoryPath.path : nil)
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
    observer = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      self.update(self.parameters)
    }
  }

  func update(_ args: [String: Any]) {
    parameters = args
    let radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
    surface.layer.cornerRadius = radius
    surface.layer.cornerCurve = .continuous
    surface.clipsToBounds = radius > 0
    let dark = args["dark"] as? Bool ?? false
    surface.overrideUserInterfaceStyle = dark ? .dark : .light
    let interactive = (args["interactive"] as? Bool) ?? (radius > 0)
    if UIAccessibility.isReduceTransparencyEnabled {
      surface.effect = nil
      surface.backgroundColor = dark ? .secondarySystemBackground : .systemBackground
    } else if #available(iOS 26.0, *) {
      // Native Liquid Glass (UIGlassEffect) — same family as system tab bars.
      let styleName = (args["style"] as? String) ?? "regular"
      let style: UIGlassEffect.Style = (styleName == "clear") ? .clear : .regular
      let effect = UIGlassEffect(style: style)
      effect.isInteractive = interactive
      surface.backgroundColor = .clear
      surface.effect = effect
    } else {
      surface.effect = UIBlurEffect(style: dark ? .systemChromeMaterialDark : .systemChromeMaterialLight)
    }
  }

  func view() -> UIView { surface }

  deinit {
    channel.setMethodCallHandler(nil)
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
  }
}

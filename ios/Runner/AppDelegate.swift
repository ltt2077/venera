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
      } else if call.method == "pickFile" {
        self.flutterResult = result
        var types: [UTType] = [.item]
        if let exts = call.arguments as? [String], !exts.isEmpty {
          var resolved: [UTType] = []
          for ext in exts {
            if let t = UTType(filenameExtension: ext) { resolved.append(t) }
          }
          if !resolved.isEmpty { types = resolved }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        self.topViewController()?.present(picker, animated: true, completion: nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Real native liquid-glass dock: UIGlassEffect as a UIKit subview overlaid on
    // FlutterView (NOT a Flutter UiKitView platform view). Platform views punch a
    // hole Impeller cannot feed into UIGlassEffect, which rendered as solid gray.
    VeneraNativeDock.shared.attach(messenger: messenger)
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
    guard let url = urls.first else {
      flutterResult?(nil)
      return
    }
    // Directory picks keep a security-scoped bookmark; file picks with asCopy land in temp.
    let needsScope = url.startAccessingSecurityScopedResource()
    if needsScope {
      self.directoryPath = url
    }
    flutterResult?(url.path)
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

/// Floating liquid-glass tab dock drawn in UIKit on top of FlutterView.
/// Uses UIGlassEffect (iOS 26+) so the system compositor samples Flutter's
/// layer under the bar — unlike Flutter UiKitView platform views.
final class VeneraNativeDock: NSObject {
  static let shared = VeneraNativeDock()

  private let effectView = UIVisualEffectView()
  private let stack = UIStackView()
  private var buttons: [UIButton] = []
  private var channel: FlutterMethodChannel?
  private weak var host: UIView?
  private var selectedIndex: Int = 0
  private var installed = false

  private override init() {
    super.init()
    effectView.clipsToBounds = true
    effectView.layer.cornerCurve = .continuous
    effectView.isUserInteractionEnabled = true

    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    effectView.contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
    ])
  }

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "venera/native_dock", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "isSupported":
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      case "show":
        self.show(args: call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "setIndex":
        if let idx = call.arguments as? Int { self.applySelection(idx) }
        else if let n = call.arguments as? NSNumber { self.applySelection(n.intValue) }
        result(nil)
      case "hide":
        self.hide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func ensureHost() -> UIView? {
    if let host, host.window != nil { return host }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.first?.windows.first
    var root = window?.rootViewController
    while let presented = root?.presentedViewController { root = presented }
    // Prefer the Flutter view so glass sits in the same hierarchy as Impeller content.
    if let flutter = root as? FlutterViewController {
      host = flutter.view
      return flutter.view
    }
    if let flutter = root?.children.compactMap({ $0 as? FlutterViewController }).first {
      host = flutter.view
      return flutter.view
    }
    host = root?.view
    return host
  }

  private func show(args: [String: Any]) {
    guard let view = ensureHost() else { return }
    let labels = (args["labels"] as? [String]) ?? []
    let symbols = (args["symbols"] as? [String]) ?? []
    let index = (args["index"] as? NSNumber)?.intValue ?? 0
    let dark = (args["dark"] as? Bool) ?? false
    let radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 28)
    let hPad = CGFloat((args["hPad"] as? NSNumber)?.doubleValue ?? 16)
    let barHeight = CGFloat((args["height"] as? NSNumber)?.doubleValue ?? 56)
    let bottomPad = CGFloat((args["bottomPad"] as? NSNumber)?.doubleValue ?? 8)
    let safeBottom = CGFloat((args["safeBottom"] as? NSNumber)?.doubleValue ?? 0)

    effectView.overrideUserInterfaceStyle = dark ? .dark : .light
    effectView.layer.cornerRadius = radius
    effectView.clipsToBounds = true
    effectView.backgroundColor = .clear

    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = true
      effectView.effect = effect
    } else {
      effectView.effect = UIBlurEffect(style: dark ? .systemChromeMaterialDark : .systemChromeMaterialLight)
    }

    rebuildButtons(labels: labels, symbols: symbols, selected: index, dark: dark)

    let width = view.bounds.width - hPad * 2
    let y = view.bounds.height - safeBottom - bottomPad - barHeight
    effectView.frame = CGRect(x: hPad, y: y, width: max(width, 0), height: barHeight)

    if effectView.superview !== view {
      effectView.removeFromSuperview()
      view.addSubview(effectView)
    } else {
      view.bringSubviewToFront(effectView)
    }
    installed = true
    selectedIndex = index
  }

  private func rebuildButtons(labels: [String], symbols: [String], selected: Int, dark: Bool) {
    buttons.forEach { $0.removeFromSuperview() }
    buttons.removeAll()
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    let count = max(labels.count, symbols.count)
    for i in 0..<count {
      var config = UIButton.Configuration.plain()
      let symbol = i < symbols.count ? symbols[i] : "circle"
      let image = UIImage(systemName: symbol)
      config.image = image
      config.title = i < labels.count ? labels[i] : nil
      config.imagePlacement = .top
      config.imagePadding = 2
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var out = incoming
        out.font = .systemFont(ofSize: 10, weight: .medium)
        return out
      }
      let btn = UIButton(configuration: config)
      btn.tag = i
      btn.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
      stack.addArrangedSubview(btn)
      buttons.append(btn)
    }
    applySelection(selected)
  }

  private func applySelection(_ index: Int) {
    selectedIndex = index
    for (i, btn) in buttons.enumerated() {
      let on = i == index
      var config = btn.configuration ?? .plain()
      config.baseForegroundColor = on
        ? .systemBlue
        : UIColor.label.withAlphaComponent(0.55)
      btn.configuration = config
    }
  }

  @objc private func tap(_ sender: UIButton) {
    let idx = sender.tag
    applySelection(idx)
    channel?.invokeMethod("onSelect", arguments: idx)
  }

  private func hide() {
    effectView.removeFromSuperview()
    installed = false
  }
}

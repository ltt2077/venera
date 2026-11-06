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

    // System controls share the Flutter controller's native hierarchy. Flutter
    // retains its content/navigation; UIKit owns its tab and toolbar materials.
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
    surface.clipsToBounds = false
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
    // UIGlassEffect shapes itself. A clipping mask flattens its optical effect.
    if #available(iOS 26.0, *) {
      surface.cornerConfiguration = .fixed(radius)
      surface.clipsToBounds = false
    } else {
      surface.layer.cornerRadius = radius
      surface.layer.cornerCurve = .continuous
      surface.clipsToBounds = radius > 0
    }
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

/// A real system tab controller, with system navigation-bar action buttons.
/// UIKit owns all material, selection, accessibility and hit-test behavior.
final class VeneraNativeChromeController: UITabBarController, UITabBarControllerDelegate {
  let header = UINavigationBar()
  private let headerItem = UINavigationItem()
  private var labels: [String] = []
  private var symbols: [String] = []
  private var actionLabels: [String] = []
  private var actionSymbols: [String] = []
  var onSelect: ((Int) -> Void)?
  var onAction: ((Int) -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self
    view.backgroundColor = .clear
    view.isOpaque = false
    view.clipsToBounds = false
    if #available(iOS 18.0, *) { mode = .tabBar }
    if #available(iOS 26.0, *) { tabBarMinimizeBehavior = .never }
    header.setItems([headerItem], animated: false)
    view.addSubview(header)
    header.accessibilityIdentifier = "venera.native.navigation"
    tabBar.accessibilityIdentifier = "venera.native.tabs"
  }

  func configure(_ args: [String: Any]) {
    loadViewIfNeeded()
    let nextLabels = args["labels"] as? [String] ?? []
    let nextSymbols = args["symbols"] as? [String] ?? []
    if nextLabels != labels || nextSymbols != symbols {
      labels = nextLabels
      symbols = nextSymbols
      let pages = labels.enumerated().map { index, title -> UIViewController in
        let page = UIViewController()
        page.view.backgroundColor = .clear
        page.view.isOpaque = false
        page.view.isUserInteractionEnabled = false
        let symbol = index < symbols.count ? symbols[index] : "circle"
        page.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: index)
        return page
      }
      setViewControllers(pages, animated: false)
    }
    let nextActionLabels = args["actionLabels"] as? [String] ?? []
    let nextActionSymbols = args["actionSymbols"] as? [String] ?? []
    if nextActionLabels != actionLabels || nextActionSymbols != actionSymbols {
      actionLabels = nextActionLabels
      actionSymbols = nextActionSymbols
      headerItem.rightBarButtonItems = actionLabels.indices.reversed().map { index in
        let symbol = index < actionSymbols.count ? actionSymbols[index] : "ellipsis"
        let item = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain,
                                   target: self, action: #selector(actionPressed(_:)))
        item.tag = index
        item.accessibilityLabel = actionLabels[index]
        item.accessibilityIdentifier = "venera.native.action.\(index)"
        return item
      }
    }
    overrideUserInterfaceStyle = (args["dark"] as? Bool ?? false) ? .dark : .light
    if let value = args["tint"] as? NSNumber {
      let argb = value.uint32Value
      let tint = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                         green: CGFloat((argb >> 8) & 255) / 255,
                         blue: CGFloat(argb & 255) / 255, alpha: 1)
      tabBar.tintColor = tint
      header.tintColor = tint
    }
    select((args["index"] as? NSNumber)?.intValue ?? 0)
  }

  func select(_ index: Int) {
    guard labels.indices.contains(index) else { return }
    if selectedIndex != index { selectedIndex = index }
    headerItem.title = labels[index]
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    header.frame = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: 44)
    view.bringSubviewToFront(header)
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    guard let index = viewControllers?.firstIndex(of: viewController) else { return }
    headerItem.title = labels[index]
    onSelect?(index)
  }

  @objc private func actionPressed(_ item: UIBarButtonItem) { onAction?(item.tag) }
}

/// Only system chrome handles touches; Flutter receives the content area.
final class VeneraNativeChromeHost: UIView {
  let controller: VeneraNativeChromeController
  init(controller: VeneraNativeChromeController) {
    self.controller = controller
    super.init(frame: .zero)
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = false
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(controller.view)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
  override func layoutSubviews() {
    super.layoutSubviews()
    controller.view.frame = bounds
  }
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden else { return nil }
    for control in [controller.header, controller.tabBar] {
      let local = control.convert(point, from: self)
      if !control.isHidden && control.point(inside: local, with: event) {
        return control.hitTest(local, with: event)
      }
    }
    return nil
  }
}

final class VeneraNativeDock: NSObject {
  static let shared = VeneraNativeDock()
  private let controller = VeneraNativeChromeController()
  private var overlay: VeneraNativeChromeHost?
  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "venera/native_dock", binaryMessenger: messenger)
    controller.onSelect = { [weak self] in self?.channel?.invokeMethod("onSelect", arguments: $0) }
    controller.onAction = { [weak self] in self?.channel?.invokeMethod("onAction", arguments: $0) }
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "isSupported":
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      case "show": result(self.show(call.arguments as? [String: Any] ?? [:]))
      case "setIndex":
        self.controller.select((call.arguments as? NSNumber)?.intValue ?? 0)
        result(nil)
      case "hide": self.hide(); result(nil)
      case "diagnostics":
        result(["attached": self.overlay?.window != nil,
                "controller": "UITabBarController", "header": "UINavigationBar",
                "tabCount": self.controller.viewControllers?.count ?? 0,
                "selectedIndex": self.controller.selectedIndex,
                "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled])
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func flutterController(in parent: UIViewController?) -> FlutterViewController? {
    guard let parent = parent else { return nil }
    if let flutter = parent as? FlutterViewController { return flutter }
    for child in parent.children {
      if let flutter = flutterController(in: child) { return flutter }
    }
    return nil
  }

  private func show(_ args: [String: Any]) -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap { $0.windows }
    let window = windows.first { $0.isKeyWindow } ?? windows.first
    // Never attach to a presented document picker or authentication controller.
    guard let parent = flutterController(in: window?.rootViewController) else { return false }
    controller.configure(args)
    if controller.parent !== parent {
      hide()
      parent.addChild(controller)
      let host = VeneraNativeChromeHost(controller: controller)
      host.frame = parent.view.bounds
      parent.view.addSubview(host)
      controller.didMove(toParent: parent)
      overlay = host
    }
    overlay?.frame = parent.view.bounds
    if let overlay = overlay { parent.view.bringSubviewToFront(overlay) }
    return overlay?.window != nil
  }

  private func hide() {
    guard controller.parent != nil else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    overlay?.removeFromSuperview()
    overlay = nil
    controller.removeFromParent()
  }
}

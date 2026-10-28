import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let registrar = flutterViewController.registrar(forPlugin: "VeneraNativeGlass")
    registrar.register(VeneraMacGlassFactory(messenger: registrar.messenger), withId: "venera/native_glass_surface")
    let glassChannel = FlutterMethodChannel(name: "venera/native_glass", binaryMessenger: registrar.messenger)
    glassChannel.setMethodCallHandler { call, result in
      if call.method == "isSupported" {
        if #available(macOS 26.0, *) { result(true) } else { result(false) }
      } else { result(FlutterMethodNotImplemented) }
    }

    super.awakeFromNib()
  }
}

private class VeneraMacGlassFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    VeneraMacGlassView(id: viewId, args: args, messenger: messenger)
  }
}

private class VeneraMacGlassView: NSView {
  private let channel: FlutterMethodChannel
  private var effect: NSView?
  private var observer: NSObjectProtocol?
  private var parameters: [String: Any] = [:]
  init(id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "venera/native_glass/\(id)", binaryMessenger: messenger)
    super.init(frame: .zero)
    wantsLayer = true
    update(args as? [String: Any] ?? [:])
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update" { self?.update(call.arguments as? [String: Any] ?? [:]); result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
    observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }; self.update(self.parameters)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func layout() { super.layout(); effect?.frame = bounds }
  func update(_ args: [String: Any]) {
    parameters = args
    let radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
    let dark = args["dark"] as? Bool ?? false
    appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    layer?.cornerRadius = radius
    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
      effect?.removeFromSuperview(); effect = nil
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    } else if #available(macOS 26.0, *) {
      let glass: NSGlassEffectView
      if let current = effect as? NSGlassEffectView { glass = current }
      else {
        effect?.removeFromSuperview()
        glass = NSGlassEffectView(frame: bounds)
        glass.autoresizingMask = [.width, .height]
        addSubview(glass); effect = glass
      }
      glass.style = .regular
      glass.cornerRadius = radius
      layer?.backgroundColor = NSColor.clear.cgColor
    }
  }
  deinit {
    channel.setMethodCallHandler(nil)
    if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
}

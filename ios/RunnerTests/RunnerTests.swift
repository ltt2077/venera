import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private var configuration: [String: Any] {
    ["labels": ["Home", "Favorites", "Explore", "Categories"],
     "symbols": ["house", "heart", "safari", "square.grid.2x2"],
     "actionLabels": ["Search", "Settings"],
     "actionSymbols": ["magnifyingglass", "gearshape"],
     "index": 0, "dark": false, "tint": NSNumber(value: 0xff007aff)]
  }

  @MainActor func testNativeSelectionKeepsControlsAndDispatchesActions() {
    let chrome = VeneraNativeChromeController()
    chrome.configure(configuration)
    let pages = chrome.viewControllers!
    let actions = chrome.header.topItem!.rightBarButtonItems!
    var changed = configuration
    changed["index"] = 2
    chrome.configure(changed)
    XCTAssertTrue(chrome.viewControllers![0] === pages[0])
    XCTAssertTrue(chrome.header.topItem!.rightBarButtonItems![0] === actions[0])
    XCTAssertEqual(chrome.selectedIndex, 2)
    XCTAssertEqual(chrome.header.topItem?.title, "Explore")
    var selected: Int?
    chrome.onSelect = { selected = $0 }
    chrome.tabBarController(chrome, didSelect: pages[1])
    XCTAssertEqual(selected, 1)
    var action: Int?
    chrome.onAction = { action = $0 }
    let search = actions.first { $0.tag == 0 }!
    _ = (search.target as? NSObject)?.perform(search.action!, with: search)
    XCTAssertEqual(action, 0)
  }

  @MainActor func testNativeHostPassesContentTouchesThrough() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    let parent = UIViewController()
    window.rootViewController = parent
    window.isHidden = false
    let chrome = VeneraNativeChromeController()
    chrome.configure(configuration)
    parent.addChild(chrome)
    let host = VeneraNativeChromeHost(controller: chrome)
    host.frame = parent.view.bounds
    parent.view.addSubview(host)
    chrome.didMove(toParent: parent)
    defer {
      chrome.willMove(toParent: nil)
      host.removeFromSuperview()
      chrome.removeFromParent()
      window.isHidden = true
      window.rootViewController = nil
    }
    window.layoutIfNeeded()
    parent.view.layoutIfNeeded()
    host.layoutIfNeeded()
    chrome.view.layoutIfNeeded()
    chrome.header.layoutIfNeeded()
    func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let button = try XCTUnwrap(descendants(chrome.header).compactMap { $0 as? UIControl }
      .first { !$0.isHidden && $0.alpha > 0 && !$0.bounds.isEmpty && $0.isUserInteractionEnabled })
    let buttonPoint = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host)
    // iOS 26 bars pass empty space through. Test a real laid-out button in a
    // window rather than assuming an arbitrary corner belongs to a control.
    XCTAssertNil(host.hitTest(CGPoint(x: host.bounds.midX, y: host.bounds.midY), with: nil))
    let hit = try XCTUnwrap(host.hitTest(buttonPoint, with: nil))
    XCTAssertTrue(hit.isDescendant(of: chrome.header))
    host.isHidden = true
    XCTAssertNil(host.hitTest(buttonPoint, with: nil))
  }

  @MainActor func testRunningFlutterAppUsesSystemChrome() async throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Native glass requires iOS 26") }
    func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
    var nativeTabs: UITabBar?
    for _ in 0..<175 {
      let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
      let views = windows.flatMap(allViews)
      nativeTabs = views.first { $0.accessibilityIdentifier == "venera.native.tabs" } as? UITabBar
      if nativeTabs != nil { break }
      try await Task.sleep(nanoseconds: 200_000_000)
    }
    XCTAssertNotNil(nativeTabs, "Flutter must attach UIKit controls, not only compile them")
    XCTAssertEqual(nativeTabs?.items?.count, 4)
    XCTAssertEqual(nativeTabs?.alpha, 1)
    print("VENERA_NATIVE_CHROME_READY UITabBarController tabs=4 UINavigationBar system-actions=2")
  }

}

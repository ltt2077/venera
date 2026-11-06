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

  @MainActor func testNativeHostPassesContentTouchesThrough() {
    let chrome = VeneraNativeChromeController()
    chrome.configure(configuration)
    let host = VeneraNativeChromeHost(controller: chrome)
    host.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    host.layoutIfNeeded()
    chrome.view.layoutIfNeeded()
    XCTAssertNil(host.hitTest(CGPoint(x: 195, y: 400), with: nil))
    XCTAssertNotNil(host.hitTest(CGPoint(x: 360, y: 22), with: nil))
    host.isHidden = true
    XCTAssertNil(host.hitTest(CGPoint(x: 360, y: 22), with: nil))
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

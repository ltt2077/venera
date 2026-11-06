# iOS 1.7.9 native UI repair

Version/build remain **1.7.9 (180)**. The bundle ID remains `com.github.wgh136.venera`.
The internal Info.plist revision is `ios-179-system-controls-1`, so this replacement
can be distinguished from older IPAs with the same version.

## Diagnosis

The previous IPA was already linked against the iOS 27.2 SDK and did not opt out
of the new design. Its Dart `Glass.usesNative` nevertheless unconditionally
returned false on iOS. Most surfaces therefore used shader glass. The native dock
was a custom UIVisualEffectView with ordinary plain buttons, not a system tab bar.
It recreated its effects/buttons every rebuild and outlived Flutter route changes.

Clipping was also applied around native materials. Apple's UIVisualEffectView
documentation warns that ancestor masks and partial alpha can suppress effects.
Native cornerConfiguration now shapes glass, while Flutter clips only the content.
The popup and route containers avoid masking the native background.

## Resulting architecture

- UITabBarController owns the main tab strip, selection interaction and accessibility.
- UINavigationBar and UIBarButtonItem own the main title and Search/Settings actions.
- Flutter retains the existing pages, source management, reading and navigation state.
- A transparent host passes content touches through; only the system bars receive input.
- Both root modal navigation and nested page navigation hide the native host. Keyboard
  visibility, app lifecycle, compact/expanded layouts and the glass toggle also govern it.
- Repeated identical updates retain controllers, tab items and toolbar buttons. No frame
  polling, screenshots used as fake backdrops, or new runtime dependency is introduced.
- iOS 26+ uses native controls/material; older supported systems keep their fallback.
  System Reduce Transparency and other accessibility preferences still apply.

## Validation and package provenance

Flutter tests check update deduplication, registration recovery, modal/lifecycle hiding
and selection restoration. XCTest checks real UIKit control identity, selection/action
callbacks, touch pass-through and native controls installed in the running Flutter app.
The workflow records a simulator screenshot for inspection. Simulator verification does
not measure hardware FPS, optical quality or battery consumption on an iPhone.

The packager checks the version, bundle ID, repair revision, iOS 26+ SDK and compiled
native class markers. It creates one Payload/Runner.app without AppleDouble files,
__MACOSX or ZIP extra fields. SHA256 and BUILD-INFO-ios.txt identify the exact binary.
The IPA is unsigned, matching the previous self-signing distribution method.

After tests pass, the workflow fast-forwards glass-cloud only if safe, replaces only
the existing iOS release asset and its metadata/checksums, and retains the previous IPA
as a workflow artifact. The original release tag and other platforms' packages stay put.

References:
- https://developer.apple.com/videos/play/wwdc2025/284/
- https://developer.apple.com/documentation/uikit/uivisualeffectview
- https://docs.flutter.dev/platform-integration/ios/platform-views

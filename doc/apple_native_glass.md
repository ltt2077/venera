# Apple native glass and desktop supplement

The first iOS/macOS/Windows 1.7.7 packages supplement the published Android
release. Each BUILD-INFO file records the exact supplement source commit;
the existing Android tag and assets are preserved.

On iOS/iPadOS 26+ the app uses UIKit `UIGlassEffect` in `UIVisualEffectView`.
On macOS 26+ it uses AppKit `NSGlassEffectView`. Runtime capability detection
keeps the existing Flutter shader fallback on older Apple OS versions and other
platforms. Turning glass off still uses the existing solid Material controls.

Native surfaces are decorative backgrounds for the existing Flutter navigation,
app bars and sheets. They never capture taps or expose duplicate accessibility
semantics. Theme/radius updates cross the platform channel only when changed;
there are no per-frame geometry messages. Native surfaces and their observers
are released with the platform view. Native Reduce Transparency is observed.

Scrolling cards use a cheap theme fill on Apple native mode rather than one
platform view per row. The main dock uses one native background instead of the
shader tab bar; visited-tab retention and inactive-ticker muting remain active.
Adaptive shader quality monitoring is disabled when native glass is available.

Platform-view synchronization has a cost. These changes remove custom shader
passes from selected chrome, but do not establish a measured FPS, energy or
memory improvement on real devices. Native compilation and Flutter regression
tests verify API availability, fallback selection and Flutter hit testing;
real-device profiling remains necessary for numerical performance claims.

The Drive signing ZIP contains Android credentials only. The iOS IPA is unsigned
and must be signed by the installer/user; macOS packages use ad-hoc signatures
and are not Developer ID notarized; Windows packages are not Authenticode signed.
No private keys are included in source or release artifacts.

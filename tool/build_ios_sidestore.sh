#!/usr/bin/env bash
# Build unsigned SideStore-safe IPA on macOS (zip -X, no 0x7875).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter build ios --release --no-codesign
APP="build/ios/iphoneos/Runner.app"
test -d "$APP"
rm -rf /tmp/venera-ipa-payload
mkdir -p /tmp/venera-ipa-payload/Payload
ditto "$APP" /tmp/venera-ipa-payload/Payload/Runner.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
OUT="$ROOT/dist/venera-${VERSION}-ios-unsigned.ipa"
mkdir -p "$ROOT/dist"
rm -f "$OUT"
( cd /tmp/venera-ipa-payload && zip -X -r "$OUT" Payload )
SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
COMMIT=$(git rev-parse --short HEAD)
cat > "$ROOT/dist/BUILD-INFO-ios.txt" <<INFO
Source commit: $(git rev-parse HEAD) ($COMMIT)
Version: ${VERSION}+${BUILD}
Unsigned SideStore IPA: zip -X -r Payload (no Unix 0x7875 extras).
Native glass: UIKit UIGlassEffect overlay dock (VeneraNativeDock) on iOS 26+.
Import: Local InkWell scoped to header; iOS pickFile via UIDocumentPicker.
SHA256: ${SHA}
INFO
echo "IPA: $OUT"
echo "SHA256: $SHA"
ls -la "$OUT"

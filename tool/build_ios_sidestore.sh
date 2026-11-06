#!/usr/bin/env bash
# Build unsigned SideStore-safe IPA on macOS (zip -X, no 0x7875).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter build ios --release --no-codesign
# Use the same validated packager as CI. Version/build stay 1.7.9 (180).
GITHUB_SHA="$(git rev-parse HEAD)" python3 tool/package_ios_native.py

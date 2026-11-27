#!/usr/bin/env bash
# Build an unsigned SideStore-compatible IPA on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter build ios --release --no-codesign
# Use the same validated packager as CI.
GITHUB_SHA="$(git rev-parse HEAD)" python3 tool/package_ios_native.py

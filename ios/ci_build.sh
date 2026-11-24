#!/usr/bin/env bash
# iOS build — run on a macOS host (this Windows dev host cannot build iOS locally).
set -euo pipefail

flutter pub get
flutter build ipa --release --obfuscate --split-per-abi

echo "iOS build artifacts:"
ls -la build/ios/ipa/ 2>/dev/null || true

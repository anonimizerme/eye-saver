#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--helper-only") ]]; then
  echo "Usage: scripts/build.sh [--helper-only]" >&2
  exit 2
fi
[[ $(uname -m) == arm64 ]] || { echo "Eye Saver requires Apple Silicon." >&2; exit 1; }
xcode_version=$(xcodebuild -version | awk '/^Xcode / { print $2 }')
[[ "$xcode_version" == 27.2* ]] || { echo "Select Xcode 27.2 before building (found $xcode_version)." >&2; exit 1; }

build_dir=${BUILD_DIR:-.build-app}
[[ "$build_dir" == /* ]] || build_dir="$PWD/$build_dir"
mkdir -p "$build_dir/ModuleCache"
xcrun swiftc -target arm64-apple-macos27.0 \
  -module-cache-path "$build_dir/ModuleCache" \
  -I Vendor/AppleSiliconDDC/Sources/AppleSiliconDDCObjC/AppleSiliconDDC \
  Vendor/AppleSiliconDDC/Sources/AppleSiliconDDC/AppleSiliconDDC.swift \
  App/Shared/MonitorSupport.swift App/Shared/DDCSequence.swift ddc-key.swift \
  -framework CoreDisplay -framework IOKit -framework CoreGraphics \
  -o "$build_dir/ddc-key"
"$build_dir/ddc-key" --self-test
[[ ${1:-} != --helper-only ]] || exit 0

identity=${SIGNING_IDENTITY:--}
team=${DEVELOPMENT_TEAM:-}
if [[ "$identity" != - && -z "$team" ]]; then
  echo "Set DEVELOPMENT_TEAM when SIGNING_IDENTITY is an Apple identity." >&2
  exit 2
fi
timestamp=--timestamp=none
[[ ${SIGNING_TIMESTAMP:-0} != 1 ]] || timestamp=--timestamp
xcodegen generate
xcodebuild -project EyeSaver.xcodeproj -scheme EyeSaver -configuration Release \
  -derivedDataPath "$build_dir" -destination 'generic/platform=macOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  "DDC_HELPER_PATH=$build_dir/ddc-key" \
  "CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=$team" \
  "SIGNING_TIMESTAMP=${SIGNING_TIMESTAMP:-0}" "OTHER_CODE_SIGN_FLAGS=$timestamp" \
  "HOST_PROFILE_SPECIFIER=${HOST_PROFILE_SPECIFIER:-}" \
  "CONTROL_PROFILE_SPECIFIER=${CONTROL_PROFILE_SPECIFIER:-}" \
  build
./scripts/verify-bundle.sh "$build_dir/Build/Products/Release/EyeSaver.app"

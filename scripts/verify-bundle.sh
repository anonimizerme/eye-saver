#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app=${1:-${BUILD_DIR:-.build-app}/Build/Products/Release/EyeSaver.app}
extension="$app/Contents/PlugIns/EyeSaverControl.appex"
helper="$app/Contents/MacOS/ddc-key"
for bundle in "$app" "$extension"; do
  test -f "$bundle/Contents/Info.plist"
  test -f "$bundle/Contents/Resources/AppIcon.icns"
  test -f "$bundle/Contents/Resources/Metadata.appintents/extract.actionsdata"
  /usr/bin/plutil -lint "$bundle/Contents/Info.plist"
  /usr/bin/codesign --verify --strict "$bundle"
done
test -x "$helper"
for binary in "$helper" "$app/Contents/MacOS/EyeSaver" "$extension/Contents/MacOS/EyeSaverControl"; do
  /usr/bin/lipo -verify_arch arm64 "$binary"
done
cmp Vendor/AppleSiliconDDC/LICENSE "$app/Contents/Resources/AppleSiliconDDC-LICENSE.txt"
/usr/bin/codesign --verify --strict "$helper"
/usr/bin/codesign --verify --deep --strict "$app"
"$helper" --self-test
echo "App, extension, ARM64 helper, icons, App Intents metadata, license and signatures verified."

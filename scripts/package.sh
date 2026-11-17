#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

kind=${1:-test}
[[ "$kind" == test || "$kind" == signed ]] || { echo "Usage: scripts/package.sh [test|signed]" >&2; exit 2; }
build_dir=${BUILD_DIR:-.build-app}
[[ "$build_dir" == /* ]] || build_dir="$PWD/$build_dir"
app="$build_dir/Build/Products/Release/EyeSaver.app"
./scripts/verify-bundle.sh "$app"
if [[ "$kind" == signed ]]; then
  team=$(/usr/bin/codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [[ -n "$team" && "$team" != 'not set' ]] || {
    echo "A signed package requires an Apple identity, not an ad-hoc signature." >&2
    exit 1
  }
fi
mkdir -p "$build_dir/artifacts"
archive="$build_dir/artifacts/EyeSaver-$kind.zip"
test ! -e "$archive" || rm "$archive"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$build_dir/artifacts" && /usr/bin/shasum -a 256 "EyeSaver-$kind.zip" > "EyeSaver-$kind.zip.sha256")
echo "Created $archive and SHA-256 checksum."

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir=${BUILD_DIR:-.build-app}
[[ "$build_dir" == /* ]] || build_dir="$PWD/$build_dir"
app=${1:-$build_dir/Build/Products/Release/EyeSaver.app}
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
./scripts/verify-bundle.sh "$app"
team=$(/usr/bin/codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[[ -n "$team" && "$team" != 'not set' ]] || { echo "Install a build signed with your Apple identity; ad-hoc CI artifacts are for testing." >&2; exit 1; }
destination="$HOME/Applications/EyeSaver.app"
[[ "$app" != "$destination" ]] || { echo "The source is already the installed application." >&2; exit 2; }
if /usr/bin/pgrep -u "$UID" -x ddc-key >/dev/null; then
  echo "Wait for the active monitor command to finish before installing." >&2
  exit 1
fi
mkdir -p "$HOME/Applications" "$build_dir"
stage_dir=$(mktemp -d "$HOME/Applications/.EyeSaver-install.XXXXXX")
backup_dir=$(mktemp -d "$build_dir/previous-install.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
/usr/bin/ditto "$app" "$stage_dir/EyeSaver.app"
/usr/bin/codesign --verify --deep --strict "$stage_dir/EyeSaver.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Unregister the build copy first; doing so after final registration can disable the installed app.
"$lsregister" -u "$app" >/dev/null 2>&1 || true
/usr/bin/pkill -u "$UID" -x EyeSaver || true
/usr/bin/pkill -u "$UID" -x EyeSaverControl || true
if [[ -e "$destination" ]]; then mv "$destination" "$backup_dir/bundle"; fi
if ! mv "$stage_dir/EyeSaver.app" "$destination"; then
  [[ ! -e "$backup_dir/bundle" ]] || mv "$backup_dir/bundle" "$destination"
  exit 1
fi
touch "$destination"
"$lsregister" -f -R -trusted "$destination"
/usr/bin/pluginkit -a "$destination/Contents/PlugIns/EyeSaverControl.appex"
/usr/bin/codesign --verify --deep --strict "$destination"
python3 - "$destination" <<'PY'
import re
import subprocess
import sys

database = subprocess.check_output([
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
    '-dump'
], text=True)
records = [record for record in database.split('--------------------------------------------------------------------------------')
           if re.search(r'^identifier:\s+local\.eyesaver\.app\s*$', record, re.MULTILINE)
           and re.search(r'^path:\s+' + re.escape(sys.argv[1]) + r'\s', record, re.MULTILINE)]
if len(records) != 1 or 'launch-disabled' in records[0]:
    raise SystemExit('EyeSaver is installed, but LaunchServices did not enable its launch. Previous bundle was retained.')
print('Installed application is registered and launch is enabled.')
PY
echo "Installed $destination; previous bundle retained in $backup_dir."
echo "Open EyeSaver once, then add Eye Saver from the Control Center controls gallery."

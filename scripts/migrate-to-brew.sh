#!/bin/bash
set -euo pipefail

token=anonimizerme/eye-saver/eye-saver
tap=anonimizerme/eye-saver
destination="$HOME/Applications/EyeSaver.app"
system_app=/Applications/EyeSaver.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
command -v brew >/dev/null || { echo "Install Homebrew before migrating Eye Saver." >&2; exit 1; }
if brew list --cask --versions eye-saver >/dev/null 2>&1; then
  echo "Homebrew already manages Eye Saver. Use: brew upgrade --cask $token" >&2
  exit 1
fi
if [[ -e "$destination" && -e "$system_app" ]]; then
  echo "Two EyeSaver.app copies exist. Keep only the intended manual installation before migrating." >&2
  exit 1
fi
source_app="$destination"
[[ ! -e "$system_app" ]] || source_app="$system_app"
[[ -d "$source_app" && ! -L "$source_app" ]] || { echo "No manual EyeSaver.app was found in ~/Applications or /Applications." >&2; exit 1; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
[[ "$identifier" == local.eyesaver.app ]] || { echo "The existing app does not have the Eye Saver bundle identifier." >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_app"
signature=$(/usr/bin/codesign -dvv "$source_app" 2>&1)
/usr/bin/grep -Eq '^Authority=(Apple Development:|Developer ID Application:)' <<< "$signature" || { echo "The manual app must have an Apple signing identity." >&2; exit 1; }
ensure_idle() {
  if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ddc-key >/dev/null; then
    echo "Wait for the active monitor command to finish before migrating." >&2
    return 1
  fi
}
ensure_idle
brew tap "$tap" https://github.com/anonimizerme/eye-saver.git
backup_root="$HOME/Library/Application Support/EyeSaver/Manual Backups"
mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/installation.XXXXXX")
chmod 700 "$backup"
restore_on_error() {
  status=$?
  trap - EXIT
  if [[ $status -ne 0 && -d "$backup/bundle" ]]; then
    if brew list --cask --versions eye-saver >/dev/null 2>&1; then
      if ! brew uninstall --cask "$token"; then
        echo "Migration failed. The original bundle is safe in $backup/bundle; Homebrew cleanup needs attention." >&2
        exit "$status"
      fi
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then mv "$destination" "$backup/failed-install"; fi
    mv "$backup/bundle" "$source_app"
    "$lsregister" -f -R -trusted "$source_app"
    /usr/bin/pluginkit -a "$source_app/Contents/PlugIns/EyeSaverControl.appex"
    echo "Migration failed; the original manual app was restored." >&2
  elif [[ $status -ne 0 && -d "$source_app" ]]; then
    "$lsregister" -f -R -trusted "$source_app"
    /usr/bin/pluginkit -a "$source_app/Contents/PlugIns/EyeSaverControl.appex"
  fi
  exit "$status"
}
trap restore_on_error EXIT
ensure_idle
/usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaver || true
/usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaverControl || true
"$lsregister" -u "$source_app" >/dev/null 2>&1 || true
mv "$source_app" "$backup/bundle"
brew install --cask "$token"
"$lsregister" -f -R -trusted "$destination"
/usr/bin/pluginkit -a "$destination/Contents/PlugIns/EyeSaverControl.appex"
echo "Homebrew now manages $destination. The previous manual app is retained in $backup/bundle."

cask "eye-saver" do
  version "1.0.0"
  sha256 "ce79395be45a9c1f0e13cdf5f8d90dd75daf0e783af3f0b5f99d8796dfaf6071"

  url "https://github.com/anonimizerme/eye-saver/releases/download/v#{version}/EyeSaver-#{version}-arm64.zip"
  name "Eye Saver"
  desc "Cycle the native Eye Saver mode on a Samsung S27B80P monitor"
  homepage "https://github.com/anonimizerme/eye-saver"

  depends_on arch: :arm64
  depends_on macos: :golden_gate

  app_path = "#{Dir.home}/Applications/EyeSaver.app"
  staged_app = "#{staged_path}/EyeSaver.app"

  app "EyeSaver.app", target: app_path

  preflight_steps do
    run "/bin/bash", args: ["-c", <<~'SHELL', "eye-saver-preflight", app_path, staged_app], writable_paths: [app_path]
      set -euo pipefail
      if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ddc-key >/dev/null; then
        echo "Wait for the active monitor command to finish before installing Eye Saver." >&2
        exit 1
      fi
      if [[ -e /Applications/EyeSaver.app || -L /Applications/EyeSaver.app ]]; then
        echo "Another EyeSaver.app exists in /Applications. Use the migration script before installing." >&2
        exit 1
      fi
      if [[ -e "$1" || -L "$1" ]]; then
        if [[ ! -d "$1" || -n "$(/bin/ls -A "$1")" ]]; then
          echo "An existing EyeSaver.app must be migrated before Homebrew can manage it." >&2
          exit 1
        fi
      fi
      identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$2/Contents/Info.plist")
      if [[ "$identifier" != local.eyesaver.app ]]; then
        echo "The release app does not have the Eye Saver bundle identifier." >&2
        exit 1
      fi
      /usr/bin/codesign --verify --deep --strict "$2"
      identity=$(/usr/bin/codesign -dvv "$2" 2>&1)
      if ! /usr/bin/grep -Eq '^Authority=(Apple Development:|Developer ID Application:)' <<< "$identity"; then
        echo "Eye Saver requires an Apple-signed release; ad-hoc builds cannot be installed by this cask." >&2
        exit 1
      fi
      if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ddc-key >/dev/null; then
        echo "A monitor command started during validation. Wait and try again." >&2
        exit 1
      fi
      /usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaver || true
      /usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaverControl || true
    SHELL
  end

  postflight_steps do
    run "/bin/bash", args: ["-c", <<~'SHELL', "eye-saver-register", app_path], writable_paths: [app_path]
      set -euo pipefail
      /usr/bin/codesign --verify --deep --strict "$1"
      # Register the containing app; macOS discovers its embedded extension automatically.
      # Explicit pluginkit registration is blocked by Homebrew's hook sandbox.
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$1"
    SHELL
  end

  uninstall_preflight_steps do
    run "/bin/bash", args: ["-c", <<~'SHELL', "eye-saver-unregister", app_path], writable_paths: [app_path]
      set -euo pipefail
      if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x ddc-key >/dev/null; then
        echo "Wait for the active monitor command to finish before removing or upgrading Eye Saver." >&2
        exit 1
      fi
      /usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaver || true
      /usr/bin/pkill -u "$(/usr/bin/id -u)" -x EyeSaverControl || true
      if [[ -d "$1" ]]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$1" >/dev/null 2>&1 || true
      fi
    SHELL
  end

  caveats <<~EOS
    Eye Saver is installed in ~/Applications/EyeSaver.app.
    Open it once, then add Eye Saver using Control Center's Edit Controls gallery.
    Close the monitor's menu before switching modes.
    #{"This prerelease uses Apple Development signing without notarization. macOS may require explicit approval on first launch." if version.to_s.include?("-")}
  EOS
end

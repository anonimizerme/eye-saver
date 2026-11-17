# Eye Saver

A macOS app with one Control Center button for the **Samsung S27B80P / ViewFinity S80PB**. Each press advances the monitor's native Eye Saver mode:

**Off → Low → High → Off**

The app closes the monitor's on-screen menu after each switch. It changes the monitor itself; it does not use macOS gamma adjustments, Night Shift, or ICC color profiles.

## Support and requirements

- Tested with a Samsung S27B80P over **DisplayPort → DisplayPort** on an Apple Silicon Mac.
- macOS **27 or later** and Apple Silicon are required.
- The checked build toolchain is **Xcode 27.2**, with its macOS SDK, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Support is based on the monitor model, not its serial number. Other Samsung models, other manufacturers, Intel Macs, and other cables or adapters are not claimed to work.

Exactly one supported external monitor must be connected. The app and Control Center disable switching when the supported model is absent or multiple matching monitors are connected. The action rechecks availability when pressed, and the helper independently checks Samsung manufacturer `SAM`, the exact product name `S27B80P`, and an external DDC service before sending anything. It never falls back to another monitor.

## Build and check

```sh
git clone git@github.com:anonimizerme/eye-saver.git
cd eye-saver
brew install xcodegen

# Point to your Xcode 27.2 installation if it has a different name.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version

./scripts/check.sh
./scripts/build.sh
./scripts/verify-bundle.sh
```

The default build is an **ad-hoc signed test build**. It produces:

- `.build-app/ddc-key`
- `.build-app/Build/Products/Release/EyeSaver.app`, including its Control Center extension, the helper, and the dependency license

To build only the helper:

```sh
./scripts/build.sh --helper-only
.build-app/ddc-key --self-test
.build-app/ddc-key --check
```

`--self-test` uses fixtures and never accesses a monitor. `--check` inspects connected monitors and DDC service availability without sending VCP requests or virtual button presses. A failed check exits with an error and sends no DDC commands.

With the monitor's menu closed, this command advances one mode and closes the menu:

```sh
.build-app/ddc-key next
```

`BUILD_DIR` overrides `.build-app` for all scripts, for example `BUILD_DIR=/tmp/eyesaver-build ./scripts/build.sh`.

## Sign and install locally

For use in Control Center, build with your own installed Apple signing identity. The project contains no personal Team ID or certificate. You can list your available identities with `security find-identity -v -p codesigning`.

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
SIGNING_IDENTITY='Apple Development' \
./scripts/build.sh

./scripts/verify-bundle.sh
./scripts/install.sh
open "$HOME/Applications/EyeSaver.app"
```

Use the full signing identity name if more than one certificate matches. The install script places the app in `~/Applications/EyeSaver.app`, retains the previous installation in the build directory, and registers the installed app and extension with macOS. Temporary build registration is removed before the installed copy is registered. This ordering matters: unregistering another copy with the same bundle identifier afterwards can leave the installed app disabled for background actions.

Keep the same bundle identifiers and signing identity when updating. The install step uses the same trusted LaunchServices registration as Xcode; it does not reset Control Center preferences or system databases.

To add the control:

1. Open Control Center and choose **Edit Controls**.
2. Find **EyeSaver** in the gallery and drag **Eye Saver** into Control Center.
3. Leave edit mode, close the monitor's on-screen menu, and press the button.

The app also has a **Next mode** button in its window. Control Center can invoke the action with the app window closed. A second press while a switch is in progress is ignored.

If an update leaves an old control binding, remove only the Eye Saver control and add it again. If the control is visible but does nothing, check the installed app's signature and registration; a successful compile alone does not validate background App Intent execution. Icon changes may take time to appear in the gallery.

## How it works

The path is:

`ControlWidgetButton → App Intent in the main app → embedded helper → DDC/CI E7 → monitor joystick events`

The sandboxed extension uses public Core Graphics display information to determine availability. The main app runs the DDC helper outside the extension sandbox. Display information is checked again when the action runs, because the Control Center presentation can be cached.

The helper enables virtual keys with VCP `E7=0A01`, then sends:

| Joystick event | Value written to VCP `E7` |
| --- | --- |
| Center | `2A05` |
| Right | `2A06` |
| Center | `2A05` |
| Left | `2A04` |
| Center | `2A05` |

The first three events select the Eye Saver icon and advance its native mode. Left and center select the close icon and dismiss the menu. Each value is written **once**, with **no retries and no reverse GET of `E7`**. Events are separated by 300 ms, with a further 700 ms after the sequence. A failed write stops the sequence; it is not repeated or redirected to another display.

## Limits and verification

- Close a manually opened monitor menu before pressing the control. The app does not read the menu's current focus.
- The app advances one mode; it cannot set an arbitrary absolute mode.
- It does not reliably read the current Off/Low/High setting, so it does not display an inferred current mode.
- A complete switch takes a few seconds. Wait for the monitor menu to close before another press.
- Monitor reconnection and Control Center refresh can be asynchronous. Runtime checks prevent a stale enabled control from bypassing validation.

The software checks cover model selection, ambiguous or missing monitors, zero writes for rejected selections, disconnect or write failure handling, duplicate-click suppression, and recovery after errors. They do not prove DDC transport or visible OSD behavior on hardware. Hardware verification is limited to the supported monitor and connection described above.

The app window and cold Control Center invocation have been checked with that monitor. Physical unplugging, including disconnection during a sequence, has not been tested on hardware; those failure paths are covered by software fixtures.

## GitHub Actions artifacts

[Build workflow](.github/workflows/build.yml) runs on pushes, pull requests, and manual dispatch using the ARM64 `xcode-27` runner and Xcode 27.2. The specialized runner image is currently a preview image. CI runs the same build and software-check scripts, verifies the nested bundle signatures and contents, and uploads a ZIP plus its SHA-256 checksum. It has no physical S27B80P, so CI does not test DDC writes, menu navigation, or the screen's response.

The default artifact is an **ad-hoc signed test build**, not a notarized release. Successful compilation and signature integrity do not establish that Control Center will accept the extension on another Mac.

For a local test package:

```sh
./scripts/package.sh test
```

The ZIP and checksum are written to `.build-app/artifacts/`. Bundle structure is preserved; generated binaries and archives are not committed.

The manual workflow also offers a separate signed mode. Configure these GitHub Secrets before selecting it:

- `BUILD_CERTIFICATE_BASE64`: the signing certificate and private key in a base64-encoded PKCS#12 file
- `P12_PASSWORD`: the PKCS#12 password
- `KEYCHAIN_PASSWORD`: a password for the temporary CI keychain
- `SIGNING_IDENTITY` and `DEVELOPMENT_TEAM`: your Apple signing identity and Team ID
- Optional `HOST_PROFILE_BASE64` and `CONTROL_PROFILE_BASE64`: provisioning profiles if your signing setup requires them

Optional notarization additionally requires `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`, with a suitable Developer ID signing setup. The workflow imports supplied secrets into a temporary keychain and cleans it up. No key is exported from a developer's Mac automatically. A signed or notarized distribution is available only after those credentials are supplied and that workflow succeeds; no ready signed release is promised by the default build. The workflow uploads Actions artifacts rather than publishing GitHub Releases.

## Dependency

DDC communication uses a minimal vendored copy of [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) by [@waydabber](https://github.com/waydabber), pinned to revision [`67ff964ab8123d9d35fadf7d8e1a7c677d31da14`](https://github.com/waydabber/AppleSiliconDDC/tree/67ff964ab8123d9d35fadf7d8e1a7c677d31da14). Its Swift source and required Objective-C headers are included under `Vendor/AppleSiliconDDC/` with the original [MIT license](Vendor/AppleSiliconDDC/LICENSE). The license is also bundled in the app.

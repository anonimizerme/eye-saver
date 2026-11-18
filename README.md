# Eye Saver

A macOS app with one Control Center button for the **Samsung S27B80P / ViewFinity S80PB**. Each press advances the monitor's native Eye Saver mode:

**Off → Low → High → Off**

The app closes the monitor's on-screen menu after each switch. It changes the monitor itself; it does not use macOS gamma adjustments, Night Shift, or ICC color profiles.

## Support and requirements

- Tested with a Samsung S27B80P over **DisplayPort → DisplayPort** on an Apple Silicon Mac.
- macOS **27 or later** and Apple Silicon are required.
- Support is based on the monitor model, not its serial number. Other Samsung models, other manufacturers, Intel Macs, and other cables or adapters are not claimed to work.

Exactly one supported external monitor must be connected. The app and Control Center disable switching when the supported model is absent or multiple matching monitors are connected. The action rechecks availability when pressed, and the helper independently checks Samsung manufacturer `SAM`, the exact product name `S27B80P`, and an external DDC service before sending anything. It never falls back to another monitor.

## Install a prebuilt app

**Development previews are available:** [1.0.0-beta.2](https://github.com/anonimizerme/eye-saver/releases/tag/v1.0.0-beta.2). They use Apple Development signing without notarization; first-launch approval is described below.

Prebuilt apps require no Xcode or local compilation. Both installation methods use the same ARM64 release ZIP and keep one installed copy at `~/Applications/EyeSaver.app`. Read the signing status on the [release page](https://github.com/anonimizerme/eye-saver/releases) before installing.

### Homebrew

This cask requires **Homebrew 7 or later**. It lives in this repository, so the tap needs an explicit URL:

```sh
brew tap anonimizerme/eye-saver https://github.com/anonimizerme/eye-saver.git
brew trust --cask anonimizerme/eye-saver/eye-saver
brew install --cask anonimizerme/eye-saver/eye-saver
open "$HOME/Applications/EyeSaver.app"
```

The narrow `brew trust --cask` command permits Homebrew to load this cask from this remote, including its later updates; it does not trust every item in the tap. Review the cask before granting trust. Trust normally persists across version updates on the same remote. This is separate from macOS first-launch approval. See [Homebrew's tap trust model](https://docs.brew.sh/Tap-Trust).

If EyeSaver is already installed manually, follow [Move a manual installation to Homebrew](#move-a-manual-installation-to-homebrew) first. The cask refuses to overwrite an unmanaged app or leave another standard-location copy with the same bundle identifier.

To update or remove the Homebrew installation:

```sh
brew update
brew upgrade --cask anonimizerme/eye-saver/eye-saver

# Remove the app when it is no longer needed.
brew uninstall --cask anonimizerme/eye-saver/eye-saver
```

The cask targets `~/Applications` directly; no `--appdir` option is needed. Wait for the monitor menu to close before installing, updating, or removing the app. Homebrew preserves the release's signing and notarization status; it does not make an unnotarized preview notarized.

### Download from GitHub Releases

1. Open [Releases](https://github.com/anonimizerme/eye-saver/releases) and select the version you want. Development previews are marked **Pre-release**.
2. Download `EyeSaver-VERSION-arm64.zip` and its matching `.zip.sha256` file. This is the Apple Silicon build.
3. Verify the checksum from the folder containing both downloads. For example, replace the version below with the selected release:

   ```sh
   cd "$HOME/Downloads"
   shasum -a 256 -c EyeSaver-1.0.0-beta.2-arm64.zip.sha256
   ```

4. Open the ZIP in Finder. Quit any running EyeSaver and wait for its monitor command to finish.
5. Move `EyeSaver.app` into your home folder's `Applications` directory. For an existing manual installation, retain a backup and replace the whole app bundle. Keep one installed copy; move the extracted app rather than keeping a second copy in Downloads or `/Applications`.
6. Open `~/Applications/EyeSaver.app` once, then follow [First launch and Control Center](#first-launch-and-control-center).

For updates, repeat these steps with the new release and verify its checksum. If Homebrew manages the app, use `brew upgrade` instead of replacing its bundle manually. To switch from Homebrew to a manual installation, uninstall the cask first.

### Signing and first-launch approval

A **development preview** is signed with Apple Development and is intended for testing. It is not Developer ID signed or notarized. It can run on a Mac that permits it, but macOS may block its first launch. This does not mean that the monitor protocol needs a different certificate. Reinstalling or updating a preview may require per-app approval again. Control Center acceptance still requires testing on the target Mac.

Only open a preview if you trust the source and the checksum matches. If macOS blocks an unnotarized app that you choose to trust, follow [Apple's per-app approval instructions](https://support.apple.com/102445): try opening it, then review **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally or remove quarantine as part of installation.

A **production release** requires Developer ID Application signing and successful notarization. The Release workflow fails when those credentials or checks are missing; it does not substitute an ad-hoc build. [Developer ID certificates require Apple Developer Program membership](https://developer.apple.com/help/glossary/developer-id-certificate/).

### First launch and Control Center

Open EyeSaver once after installing it. Then:

1. Open Control Center and choose **Edit Controls**.
2. Find **EyeSaver** in the gallery and drag **Eye Saver** into Control Center.
3. Leave edit mode, close the monitor's on-screen menu, and press the button.

The app also has a **Next mode** button in its window. Control Center can invoke the action with the app window closed and checks the connected monitor on each press. A second press while a switch is in progress is ignored.

If an update leaves an old control binding, remove only the Eye Saver control and add it again. If the control is visible but does nothing, check the installed app's signature and registration; a successful compile alone does not validate background App Intent execution. Icon changes may take time to appear in the gallery.

### Move a manual installation to Homebrew

Do not install a second copy over the manually installed app. After adding the tap, run the migration helper from that checkout:

```sh
brew tap anonimizerme/eye-saver https://github.com/anonimizerme/eye-saver.git
brew trust --cask anonimizerme/eye-saver/eye-saver
bash "$(brew --repository anonimizerme/eye-saver)/scripts/migrate-to-brew.sh"
```

The helper preserves the manual installation under `~/Library/Application Support/EyeSaver/Manual Backups` before installing the cask and restores it if installation fails. Backups use a non-`.app` name to avoid registering a second copy and survive removal of the tap. The helper does not compile the app. Open the installed app once afterwards and check the control with the app window closed. If you already have another EyeSaver copy in `/Applications`, resolve that duplicate before migrating; do not leave two copies with the same bundle identifier.

## Build from source

Source builds additionally require **Xcode 27.2**, its macOS SDK, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

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

See [First launch and Control Center](#first-launch-and-control-center) after installing.

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

Browser download and manual installation of beta.1, migration to Homebrew, cask installation/removal/reinstallation, and a beta.1 → beta.2 upgrade were verified on macOS 27.2.1 with that monitor. Cold Control Center invocation worked after both installation methods; three successive presses after the upgrade closed the monitor menu without opening an app window. These checks validate development previews on this Mac, not notarized distribution or acceptance on other Macs.

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

Optional notarization additionally requires `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`, with a suitable Developer ID signing setup. The workflow imports supplied secrets into a temporary keychain and cleans it up. No key is exported from a developer's Mac automatically. The Build workflow uploads Actions artifacts; it does not publish GitHub Releases. An Apple Development signed artifact remains a test build without notarization.

## Publish a GitHub Release

Maintainers use the separate **Release** workflow in [GitHub Actions](https://github.com/anonimizerme/eye-saver/actions/workflows/release.yml):

1. Choose **Run workflow**.
2. Enter a version without a leading `v`, the source branch/tag/commit to build, and the signing mode.
3. Keep **Draft** enabled to review the result before publishing, or disable it to publish immediately.
4. For a test preview, choose `development-preview` and a prerelease version such as `1.0.0-beta.1`. For a production release, choose `production` and provide Developer ID and notarization credentials.

The workflow resolves the selected source ref to one commit. Tag `vVERSION` points to that exact commit; a conflicting existing tag is rejected. It reuses the build, software-check, and packaging scripts, then attaches `EyeSaver-VERSION-arm64.zip` and its SHA-256 checksum to the release. App and extension use the numeric `MAJOR.MINOR.PATCH` version with the same build number. Preview releases are explicitly marked prereleases and describe their Apple Development signing status.

Every release executable must have a secure Apple timestamp. If Apple timestamp access fails, the release stops; retry it after connectivity recovers rather than disabling the timestamp check.

Only the release publishing and cask update jobs have `contents: write`. Push and pull-request checks retain read-only permissions. Production publishing requires successful Developer ID verification and notarization, with no fallback to an ad-hoc or development build.

After a release is published, [Update Homebrew cask](.github/workflows/update-cask.yml) downloads the public application ZIP and its `.sha256` file. If the checksum matches, it commits the version and checksum to `main`. This applies to stable releases and prereleases. Publishing an older version leaves a newer cask pin in place.

For a tag created before this workflow was added, run **Update Homebrew cask** from `main` and enter the published tag. After a cask update, verify installation and upgrade before announcing the new Homebrew version.

## Dependency

DDC communication uses a minimal vendored copy of [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) by [@waydabber](https://github.com/waydabber), pinned to revision [`67ff964ab8123d9d35fadf7d8e1a7c677d31da14`](https://github.com/waydabber/AppleSiliconDDC/tree/67ff964ab8123d9d35fadf7d8e1a7c677d31da14). Its Swift source and required Objective-C headers are included under `Vendor/AppleSiliconDDC/` with the original [MIT license](Vendor/AppleSiliconDDC/LICENSE). The license is also bundled in the app.
